# frozen_string_literal: true

module Bulkrax
  class CsvFileSetEntry < CsvEntry
    def factory_class
      ::FileSet
    end

    def add_path_to_file
      parsed_metadata['file'].each_with_index do |filename, i|
        path_to_file = File.join(parser.path_to_files, filename)
        parsed_metadata['file'][i] = path_to_file
      end
    end
  end
end
