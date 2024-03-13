# frozen_string_literal: true

module Bulkrax
  module FileSetEntryBehavior
    extend ActiveSupport::Concern

    included do
      self.default_work_type = "::FileSet"
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

        parsed_metadata['file'][i] = path_to_file
      end
      parsed_metadata['file'].delete('')

      raise ::StandardError, "one or more file paths are invalid: #{parsed_metadata['file'].join(', ')}" unless parsed_metadata['file'].map { |file_path| ::File.file?(file_path) }.all?

      parsed_metadata['file']
    end

    def validate_presence_of_filename!
      return if parsed_metadata&.[](file_reference)&.map(&:present?)&.any?

      raise StandardError, 'File set must have a filename'
    end

    def validate_presence_of_parent!
      return if parsed_metadata[related_parents_parsed_mapping]&.map(&:present?)&.any?

      raise StandardError, 'File set must be related to at least one work'
    end

    def parent_jobs
      false # FileSet relationships are handled in ObjectFactory#create_file_set
    end

    def child_jobs
      raise ::StandardError, "A #{Bulkrax.file_model_class} cannot be a parent of a #{Bulkrax.collection_model_class}, Work, or other #{Bulkrax.file_model_class}"
    end
  end
end
