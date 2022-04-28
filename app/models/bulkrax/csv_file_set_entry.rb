# frozen_string_literal: true

module Bulkrax
  class CsvFileSetEntry < CsvEntry
    def factory_class
      ::FileSet
    end

    def add_path_to_file
      parsed_metadata['file'].each_with_index do |filename, i|
        path_to_file = ::File.join(parser.path_to_files, filename)

        parsed_metadata['file'][i] = path_to_file
      end
      raise ::StandardError, "one or more file paths are invalid: #{parsed_metadata['file'].join(', ')}" unless parsed_metadata['file'].map { |file_path| ::File.file?(file_path) }.all?

      parsed_metadata['file']
    end

    def validate_presence_of_filename!
      return if parsed_metadata&.[]('file')&.map(&:present?)&.any?

      raise StandardError, 'File set must have a filename'
    end

    def validate_presence_of_parent!
      return if parsed_metadata[related_parents_parsed_mapping]&.map(&:present?)&.any?

      raise StandardError, 'File set must be related to at least one work'
    end
  end
end
