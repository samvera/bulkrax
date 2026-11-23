# frozen_string_literal: true

module Bulkrax
  module FileSetEntryBehavior
    class FileNameError < StandardError
    end

    class OrphanFileSetError < StandardError
    end

    class FilePathError < StandardError
    end

    extend ActiveSupport::Concern

    included do
      self.default_work_type = Bulkrax.file_model_class.to_s
    end

    def file_reference
      return 'file' if parsed_metadata&.[]('file')&.map(&:present?)&.any?
      return 'remote_files' if parsed_metadata&.[]('remote_files')&.map(&:present?)&.any?
    end

    def add_path_to_file
      return unless file_reference == 'file'

      parsed_metadata['file'].each_with_index do |filename, i|
        next if filename.blank?

        path_to_file = parser.path_to_files(filename: filename)

        parsed_metadata['file'][i] = path_to_file if path_to_file.present?
      end
      parsed_metadata['file'].delete('')

      raise FilePathError, "one or more file paths are invalid: #{parsed_metadata['file'].join(', ')}" unless parsed_metadata['file'].map { |file_path| ::File.file?(file_path) }.all?

      parsed_metadata['file']
    end

    def validate_presence_of_filename!
      return if parsed_metadata&.[](file_reference)&.map(&:present?)&.any?

      raise FileNameError, 'File set must have a filename'
    end

    def validate_presence_of_parent!
      return if parsed_metadata[related_parents_parsed_mapping]&.map(&:present?)&.any?

      raise OrphanFileSetError, 'File set must be related to at least one work'
    end

    # A new file set whose row names no visibility is left without one when the
    # object factory gives such a file set its work's visibility, embargo and
    # lease (ObjectFactoryInterface.file_sets_take_work_visibility?). Any other
    # row without one, including a row updating an existing file set, takes the
    # importer's visibility as other entries do.
    def add_visibility
      return super if parsed_metadata['visibility'].present? || !Bulkrax.object_factory.file_sets_take_work_visibility?

      existing_file_set = factory.find
      # The factory copies parsed_metadata when it is built, so import needs one built from the finished metadata
      @factory = nil
      super if existing_file_set.present?
    end

    def parent_jobs
      false # FileSet relationships are handled in ObjectFactory#create_file_set
    end

    def child_jobs
      raise ::StandardError, "A #{Bulkrax.file_model_class} cannot be a parent of a #{Bulkrax.collection_model_class}, Work, or other #{Bulkrax.file_model_class}"
    end
  end
end
