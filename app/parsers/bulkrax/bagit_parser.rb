# frozen_string_literal: true

module Bulkrax
  class BagitParser < CsvParser # rubocop:disable Metrics/ClassLength
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

    def path_to_files(filename:)
      @path_to_files ||= Dir.glob(File.join(import_file_path, '**/data', filename)).first
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
        get_data(bag, data)
      end

      @records = @records.flatten
    end

    def get_data(bag, data)
      if entry_class == CsvEntry
        data = data.map do |data_row|
          record_data = entry_class.data_for_entry(data_row, source_identifier, self)
          next record_data if importerexporter.metadata_only?

          record_data[:file] = bag.bag_files.join('|') if ::Hyrax.config.curation_concerns.include? record_data[:model]&.constantize
          record_data
        end
      else
        data = entry_class.data_for_entry(data, source_identifier, self)
        data[:file] = bag.bag_files.join('|') unless importerexporter.metadata_only?
      end

      data
    end

    def create_works
      entry_class == CsvEntry ? super : create_rdf_works
    end

    def create_rdf_works
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

    def total
      @total = importer.parser_fields['total'] || 0 if importer?

      @total = if exporter?
                 limit.nil? || limit.zero? ? current_record_ids.count : limit
               end

      return @total || 0
    rescue StandardError
      @total = 0
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

    # export methods

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def write_files
      require 'open-uri'
      require 'socket'

      folder_count = 1
      records_in_folder = 0

      importerexporter.entries.where(identifier: current_record_ids)[0..limit || total].each do |entry|
        record = ActiveFedora::Base.find(entry.identifier)
        next unless Hyrax.config.curation_concerns.include?(record.class)

        bag_entries = [entry]
        file_set_entry = Bulkrax::CsvFileSetEntry.where("parsed_metadata LIKE '%#{record.id}%'").first
        bag_entries << file_set_entry unless file_set_entry.nil?

        records_in_folder += bag_entries.count
        if records_in_folder > 1000
          folder_count += 1
          records_in_folder = bag_entries.count
        end

        bag ||= BagIt::Bag.new setup_bagit_folder(folder_count, entry.identifier)

        record.file_sets.each do |fs|
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

        CSV.open(setup_csv_metadata_export_file(folder_count, entry.identifier), "w", headers: export_headers, write_headers: true) do |csv|
          bag_entries.each { |csv_entry| csv << csv_entry.parsed_metadata }
        end

        write_triples(folder_count, entry)
        bag.manifest!(algo: 'sha256')
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def setup_csv_metadata_export_file(folder_count, id)
      path = File.join(importerexporter.exporter_export_path, folder_count.to_s)
      FileUtils.mkdir_p(path) unless File.exist?(path)

      File.join(path, id, 'metadata.csv')
    end

    def key_allowed(key)
      !Bulkrax.reserved_properties.include?(key) &&
        new_entry(entry_class, 'Bulkrax::Exporter').field_supported?(key) &&
        key != source_identifier.to_s
    end

    def setup_triple_metadata_export_file(folder_count, id)
      path = File.join(importerexporter.exporter_export_path, folder_count.to_s)
      FileUtils.mkdir_p(path) unless File.exist?(path)

      File.join(path, id, 'metadata.nt')
    end

    def setup_bagit_folder(folder_count, id)
      path = File.join(importerexporter.exporter_export_path, folder_count.to_s)
      FileUtils.mkdir_p(path) unless File.exist?(path)

      File.join(path, id)
    end

    def write_triples(folder_count, e)
      sd = SolrDocument.find(e.identifier)
      return if sd.nil?

      req = ActionDispatch::Request.new({ 'HTTP_HOST' => Socket.gethostname })
      rdf = Hyrax::GraphExporter.new(sd, req).fetch.dump(:ntriples)
      File.open(setup_triple_metadata_export_file(folder_count, e.identifier), "w") do |triples|
        triples.write(rdf)
      end
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

    # use the version of this method from the application parser instead
    def real_import_file_path
      return importer_unzip_path if file? && zip?
      parser_fields['import_file_path']
    end
  end
end
