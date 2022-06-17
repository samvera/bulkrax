# frozen_string_literal: true

module Bulkrax
  class BagitParser < ApplicationParser # rubocop:disable Metrics/ClassLength
    include ExportBehavior

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
      rdf_format = parser_fields&.[]('metadata_format') == "Bulkrax::RdfEntry"
      rdf_format ? RdfEntry : CsvEntry
    end
    alias work_entry_class entry_class

    def collection_entry_class; end

    def file_set_entry_class
      # TODO: is a conditional needed for file sets imported through rdf?
      CsvFileSetEntry
    end

    def path_to_files(parent_id:)
      @path_to_files ||= File.join(
        zip? ? importer_unzip_path : File.dirname(import_file_path), parent_id, 'data'
      )
    end

    # Take a random sample of 10 metadata_paths and work out the import fields from that
    def import_fields
      raise StandardError, 'No metadata files were found' if metadata_paths.blank?
      @import_fields ||= metadata_paths.sample(10).map do |path|
        entry_class.fields_from_data(entry_class.read_data(path))
      end.flatten.compact.uniq
    end

    # Create an Array of all metadata records
    def records(_opts = {})
      raise StandardError, 'No BagIt records were found' if bags.blank?
      @records ||= bags.map do |bag|
        path = metadata_path(bag)
        raise StandardError, 'No metadata files were found' if path.blank?
        data = entry_class.read_data(path)
        data = data.map do |d|
          record_data = entry_class.data_for_entry(d, source_identifier, self)
          next record_data if importerexporter.metadata_only?

          record_data[:file] = bag.bag_files.join('|') if Hyrax.config.curation_concerns.include? record_data[:model].constantize
          record_data
        end

        data
      end

      @records = @records.flatten
    end

    # Collections are not imported or with bagit
    def create_collections; end

    # TODO: not yet supported
    def create_relationships; end

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

    def current_record_ids
      @work_ids = []
      @collection_ids = []
      @file_set_ids = []

      case importerexporter.export_from
      when 'all'
        @work_ids = ActiveFedora::SolrService.query("has_model_ssim:(#{Hyrax.config.curation_concerns.join(' OR ')}) #{extra_filters}", method: :post, rows: 2_147_483_647).map(&:id)
        @file_set_ids = ActiveFedora::SolrService.query("has_model_ssim:FileSet #{extra_filters}", method: :post, rows: 2_147_483_647).map(&:id)
      when 'collection'
        @work_ids = ActiveFedora::SolrService.query("member_of_collection_ids_ssim:#{importerexporter.export_source + extra_filters}", method: :post, rows: 2_000_000_000).map(&:id)
      when 'worktype'
        @work_ids = ActiveFedora::SolrService.query("has_model_ssim:#{importerexporter.export_source + extra_filters}", method: :post, rows: 2_000_000_000).map(&:id)
      when 'importer'
        set_ids_for_exporting_from_importer
      end

      @work_ids + @collection_ids + @file_set_ids
    end

    # Set the following instance variables: @work_ids, @collection_ids, @file_set_ids
    # @see #current_record_ids
    def set_ids_for_exporting_from_importer
      entry_ids = Importer.find(importerexporter.export_source).entries.pluck(:id)
      complete_statuses = Status.latest_by_statusable
                                .includes(:statusable)
                                .where('bulkrax_statuses.statusable_id IN (?) AND bulkrax_statuses.statusable_type = ? AND status_message = ?', entry_ids, 'Bulkrax::Entry', 'Complete')

      complete_entry_identifiers = complete_statuses.map { |s| s.statusable&.identifier&.gsub(':', '\:') }
      extra_filters = extra_filters.presence || '*:*'

      { :@work_ids => ::Hyrax.config.curation_concerns, :@collection_ids => [::Collection], :@file_set_ids => [::FileSet] }.each do |instance_var, models_to_search|
        instance_variable_set(instance_var, ActiveFedora::SolrService.post(
          extra_filters.to_s,
          fq: [
            %(#{::Solrizer.solr_name(work_identifier)}:("#{complete_entry_identifiers.join('" OR "')}")),
            "has_model_ssim:(#{models_to_search.join(' OR ')})"
          ],
          fl: 'id',
          rows: 2_000_000_000
        )['response']['docs'].map { |obj| obj['id'] })
      end
    end

    # export methods

    def create_new_entries
      current_record_ids.each_with_index do |id, index|
        break if limit_reached?(limit, index)

        this_entry_class = if @collection_ids.include?(id)
                             collection_entry_class
                           elsif @file_set_ids.include?(id)
                             file_set_entry_class
                           else
                             entry_class
                           end
        new_entry = find_or_create_entry(this_entry_class, id, 'Bulkrax::Exporter')

        begin
          entry = ExportWorkJob.perform_now(new_entry.id, current_run.id)
        rescue => e
          Rails.logger.info("#{e.message} was detected during export")
        end

        self.headers |= entry.parsed_metadata.keys if entry
      end
    end
    alias create_from_collection create_new_entries
    alias create_from_importer create_new_entries
    alias create_from_worktype create_new_entries
    alias create_from_all create_new_entries

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def write_files
      require 'open-uri'
      require 'socket'
      importerexporter.entries.where(identifier: current_record_ids)[0..limit || total].each do |entry|
        work = ActiveFedora::Base.find(entry.identifier)
        next unless Hyrax.config.curation_concerns.include?(work.class)
        bag = BagIt::Bag.new setup_bagit_folder(entry.identifier)
        bag_entries = [entry]

        work.file_sets.each do |fs|
          if @file_set_ids.present?
            file_set_entry = Bulkrax::CsvFileSetEntry.where("parsed_metadata LIKE '%#{fs.id}%'").first
            bag_entries << file_set_entry unless file_set_entry.nil?
          end

          file_name = filename(fs)
          next if file_name.blank?
          io = open(fs.original_file.uri)
          file = Tempfile.new([file_name, File.extname(file_name)], binmode: true)
          file.write(io.read)
          file.close
          begin
            bag.add_file(file_name, file.path)
          rescue => e
            entry.status_info(e)
            status_info(e)
          end
        end

        CSV.open(setup_csv_metadata_export_file(entry.identifier), "w", headers: export_headers, write_headers: true) do |csv|
          bag_entries.each { |csv_entry| csv << csv_entry.parsed_metadata }
        end
        write_triples(entry)
        bag.manifest!(algo: 'sha256')
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def setup_csv_metadata_export_file(id)
      File.join(importerexporter.exporter_export_path, id, 'metadata.csv')
    end

    def key_allowed(key)
      !Bulkrax.reserved_properties.include?(key) &&
        new_entry(entry_class, 'Bulkrax::Exporter').field_supported?(key) &&
        key != source_identifier.to_s
    end

    # All possible column names
    def export_headers
      headers = sort_headers(self.headers)

      # we don't want access_control_id exported and we want file at the end
      headers.delete('access_control_id') if headers.include?('access_control_id')

      # add the headers below at the beginning or end to maintain the preexisting export behavior
      headers.prepend('model')
      headers.prepend(source_identifier.to_s)
      headers.prepend('id')

      headers.uniq
    end

    def object_names
      return @object_names if @object_names

      @object_names = mapping.values.map { |value| value['object'] }
      @object_names.uniq!.delete(nil)

      @object_names
    end

    def sort_headers(headers)
      # converting headers like creator_name_1 to creator_1_name so they get sorted by numerical order
      # while keeping objects grouped together
      headers.sort_by do |item|
        number = item.match(/\d+/)&.[](0) || 0.to_s
        sort_number = number.rjust(4, "0")
        object_prefix = object_names.detect { |o| item.match(/^#{o}/) } || item
        remainder = item.gsub(/^#{object_prefix}_/, '').gsub(/_#{number}/, '')
        "#{object_prefix}_#{sort_number}_#{remainder}"
      end
    end

    def setup_triple_metadata_export_file(id)
      File.join(importerexporter.exporter_export_path, id, 'metadata.nt')
    end

    def setup_bagit_folder(id)
      File.join(importerexporter.exporter_export_path, id)
    end

    def write_triples(e)
      sd = SolrDocument.find(e.identifier)
      return if sd.nil?

      req = ActionDispatch::Request.new({ 'HTTP_HOST' => Socket.gethostname })
      rdf = Hyrax::GraphExporter.new(sd, req).fetch.dump(:ntriples)
      File.open(setup_triple_metadata_export_file(e.identifier), "w") do |triples|
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
      @bags = new_bag ? [new_bag] : Dir.glob("#{import_file_path}/**/*").map { |d| bag(d) }
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
