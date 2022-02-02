# frozen_string_literal: true

module Bulkrax
  class BagitParser < ApplicationParser
    def self.export_supported?
      false # @todo will be supported
    end

    def valid_import?
      return true if import_fields.present?
    rescue => e
      status_info(e)
      false
    end

    def entry_class
      parser_fields['metadata_format'].constantize
    end

    def collection_entry_class
      parser_fields['metadata_format'].gsub('Entry', 'CollectionEntry').constantize
    rescue
      Entry
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
        data = entry_class.data_for_entry(data, source_identifier)
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
        increment_counters(index)
      end
      importer.record_status
    rescue StandardError => e
      status_info(e)
    end

    def collections
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      records.map { |r| r[collection_field_mapping].split(/\s*[;|]\s*/) if r[collection_field_mapping].present? }.flatten.compact.uniq
    end

    def collections_total
      collections.size
    end

    # TODO: change to differentiate between collection and work records when adding ability to import collection metadata
    def works_total
      total
    end

    def total
      metadata_paths.count
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
