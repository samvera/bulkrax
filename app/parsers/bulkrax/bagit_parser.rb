# frozen_string_literal: true

module Bulkrax
  class BagitParser < ApplicationParser
    def self.export_supported?
      true
    end

    def valid_import?
      return true if import_fields.present?
    rescue => e
      status_info(e)
      false
    end

    def entry_class
      csv_format = parser_fields&.[]('metadata_format') == "Bulkrax::RdfEntry"
      csv_format ? RdfEntry : CsvEntry
    end

    def collection_entry_class
      csv_format = parser_fields&.[]('metadata_format') == "Bulkrax::RdfEntry"
      csv_format ? RdfCollectionEntry : CsvCollectionEntry
    end

    def file_set_entry_class
      csv_format = parser_fields&.[]('metadata_format') == "Bulkrax::RdfEntry"
      csv_format ? RdfFileSetEntry : CsvFileSetEntry
    end

    # Take a random sample of 10 metadata_paths and work out the import fields from that
    def import_fields
      raise StandardError, 'No metadata files were found' if metadata_paths.blank?
      @import_fields ||= metadata_paths.sample(10).map do |path|
        entry_class.fields_from_data(entry_class.read_data(path))
      end.flatten.compact.uniq
    end

    # Assume a single metadata record per path
    # Create an Array of all metadata records, one per file
    def records(_opts = {})
      raise StandardError, 'No BagIt records were found' if bags.blank?
      @records ||= bags.map do |bag|
        path = metadata_path(bag)
        raise StandardError, 'No metadata files were found' if path.blank?
        data = entry_class.read_data(path)
        data = entry_class.data_for_entry(data, source_identifier, self)
        data[:file] = bag.bag_files.join('|') unless importerexporter.metadata_only?
        data
      end
    end

    # Find or create collections referenced by works
    # If the import data also contains records for these works, they will be updated
    # during create works
    def create_collections
      collections.each_with_index do |collection, index|
        next if collection.blank?
        metadata = {
          title: [collection],
          work_identifier => [collection],
          visibility: 'open',
          collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid
        }
        new_entry = find_or_create_entry(collection_entry_class, collection, 'Bulkrax::Importer', metadata)
        ImportCollectionJob.perform_now(new_entry.id, current_run.id)
        increment_counters(index, collection: true)
      end
    end

    def create_works
      records.each_with_index do |record, index|
        next unless record_has_source_identifier(record, index)
        break if limit_reached?(limit, index)

        seen[record[source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, record[source_identifier], 'Bulkrax::Importer', record)
        if record[:delete].present?
          DeleteWorkJob.send(perform_method, new_entry, current_run)
        else
          ImportWorkJob.send(perform_method, new_entry.id, current_run.id)
        end
        increment_counters(index, work: true)
      end
      importer.record_status
    rescue StandardError => e
      status_info(e)
    end

    def collections
      records.map { |r| r[related_parents_parsed_mapping].split(/\s*[;|]\s*/) if r[related_parents_parsed_mapping].present? }.flatten.compact.uniq
    end

    def collections_total
      collections.size
    end

    # TODO: change to differentiate between collection and work records when adding ability to import collection metadata
    def works_total
      total
    end

    def total
      importerexporter.entries.count
    end

    def extra_filters
      output = ""
      if importerexporter.start_date.present?
        start_dt = importerexporter.start_date.to_datetime.strftime('%FT%TZ')
        finish_dt = importerexporter.finish_date.present? ? importerexporter.finish_date.to_datetime.end_of_day.strftime('%FT%TZ') : "NOW"
        output += " AND system_modified_dtsi:[#{start_dt} TO #{finish_dt}]"
      end
      output += importerexporter.work_visibility.present? ? " AND visibility_ssi:#{importerexporter.work_visibility}" : ""
      output += importerexporter.workflow_status.present? ? " AND workflow_state_name_ssim:#{importerexporter.workflow_status}" : ""
      output
    end

    def current_work_ids
      case importerexporter.export_from
      # TODO: handle 'all' case
      when 'collection'
        ActiveFedora::SolrService.query("member_of_collection_ids_ssim:#{importerexporter.export_source + extra_filters}", rows: 2_000_000_000).map(&:id)
      when 'worktype'
        ActiveFedora::SolrService.query("has_model_ssim:#{importerexporter.export_source + extra_filters}", rows: 2_000_000_000).map(&:id)
      when 'importer'
        entry_ids = Bulkrax::Importer.find(importerexporter.export_source).entries.pluck(:id)
        complete_statuses = Bulkrax::Status.latest_by_statusable
                                .includes(:statusable)
                                .where('bulkrax_statuses.statusable_id IN (?) AND bulkrax_statuses.statusable_type = ? AND status_message = ?', entry_ids, 'Bulkrax::Entry', 'Complete')
        complete_entry_identifiers = complete_statuses.map { |s| s.statusable&.identifier&.gsub(':', '\:') }
        extra_filters = extra_filters.presence || '*:*'
        resp = ActiveFedora::SolrService.get(
          extra_filters.to_s,
          fq: "#{work_identifier}_sim:(#{complete_entry_identifiers.join(' OR ')})",
          fl: 'id',
          rows: 2_000_000_000
        )['response']['docs']
        resp.map { |obj| obj['id'] }
      end
    end

    def create_new_entries
      current_work_ids.each_with_index do |wid, index|
        break if limit_reached?(limit, index)
        new_entry = find_or_create_entry(entry_class, wid, 'Bulkrax::Exporter')
        Bulkrax::ExportWorkJob.perform_now(new_entry.id, current_run.id)
      end
    end
    alias create_from_collection create_new_entries
    alias create_from_importer create_new_entries
    alias create_from_worktype create_new_entries
    alias create_from_all create_new_entries

    def write_files
      require 'open-uri'
      require 'socket'
      require 'bagit' # TODO: check if needed here?
      require 'tempfile' # TODO: check if needed here?
      importerexporter.entries.where(source_identifier: current_work_ids)[0..limit || total].each do |e|
        bag = BagIt::Bag.new setup_bagit_folder(e.source_identifier)
        w = ActiveFedora::Base.find(e.source_identifier)
        w.file_sets.each do |fs|
          file_name = filename(fs)
          next if file_name.blank?
          io = open(fs.original_file.uri)
          file = Tempfile.new([file_name, File.extname(file_name)], binmode: true)
          file.write(io.read)
          file.close
          bag.add_file(file_name, file.path)
        end
        CSV.open(setup_csv_metadata_export_file(e.source_identifier), "w", headers: export_headers, write_headers: true) do |csv|
          csv << e.parsed_metadata
        end
        write_triples(e)
        bag.manifest!(algo: 'sha256')
      end
    end

    def setup_bagit_folder(id)
      File.join(importerexporter.exporter_export_path, id)
    end

    def setup_csv_metadata_export_file(id)
      File.join(importerexporter.exporter_export_path, id, 'metadata.csv')
    end

    def export_headers
      headers = ['id']
      headers << source_identifier.to_s
      headers << 'model'
      headers << 'collections'
      importerexporter.mapping.each_key { |key| headers << key if key_allowed(key) }
      headers << 'file'
      headers.uniq
    end

    def write_triples(e)
      sd = SolrDocument.find(e.source_identifier)
      return if sd.nil?

      req = ActionDispatch::Request.new({'HTTP_HOST' => Socket.gethostname})
      rdf = Hyrax::GraphExporter.new(sd, req).fetch.dump(:ntriples)
      File.open(setup_triple_metadata_export_file(e.source_identifier), "w") do |triples|
        triples.write(rdf)
      end
    end

    def required_elements?(keys)
      return if keys.blank?
      !required_elements.map { |el| keys.map(&:to_s).include?(el) }.include?(false)
    end

    # @todo - investigate getting directory structure
    # @todo - investigate using perform_later, and having the importer check for
    #   DownloadCloudFileJob before it starts
    def retrieve_cloud_files(files)
      # There should only be one zip file for Bagit, take the first
      return if files['0'].blank?
      target_file = File.join(path_for_import, files['0']['file_name'].tr(' ', '_'))
      # Now because we want the files in place before the importer runs
      Bulkrax::DownloadCloudFileJob.perform_now(files['0'], target_file)
      return target_file
    end

    private

    def bags
      return @bags if @bags.present?
      new_bag = bag(import_file_path)
      @bags = if new_bag
                [new_bag]
              else
                Dir.glob("#{import_file_path}/**/*").map { |d| bag(d) }
              end
      @bags.delete(nil)
      raise StandardError, 'No valid bags found' if @bags.blank?
      return @bags
    end

    # Gather the paths to all bags; skip any stray files
    def bag_paths
      bags.map(&:bag_dir)
    end

    def metadata_file_name
      raise StandardError, 'The metadata file name must be specified' if parser_fields['metadata_file_name'].blank?
      parser_fields['metadata_file_name']
    end

    # Gather the paths to all metadata files matching the metadata_file_name
    def metadata_paths
      @metadata_paths ||= bag_paths.map do |b|
        Dir.glob("#{b}/**/*").select { |f| File.file?(f) && f.ends_with?(metadata_file_name) }
      end.flatten.compact
    end

    def metadata_path(bag)
      Dir.glob("#{bag.bag_dir}/**/*").detect { |f| File.file?(f) && f.ends_with?(metadata_file_name) }
    end

    def bag(path)
      return nil unless path && File.exist?(File.join(path, 'bagit.txt'))
      bag = BagIt::Bag.new(path)
      return nil unless bag.valid?
      bag
    end
  end
end
