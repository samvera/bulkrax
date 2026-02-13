# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    ##
    # Validates file references in CSV against zip archive contents
    #
    # Responsibilities:
    # - Count file references in CSV data
    # - Extract list of files from zip archive
    # - Identify files referenced in CSV but missing from zip
    # - Count files successfully found in zip
    #
    # @example
    #   validator = FileValidator.new(csv_data, zip_file)
    #   validator.count_references       # => 10
    #   validator.missing_files          # => ['image1.jpg', 'doc.pdf']
    #   validator.found_files_count      # => 8
    #
    class FileValidator
      attr_reader :csv_data, :zip_file

      # Initialize the file validator
      #
      # @param csv_data [Array<Hash>] Array of parsed CSV rows with :file key
      # @param zip_file [File, ActionDispatch::Http::UploadedFile, nil] Optional zip archive
      def initialize(csv_data, zip_file = nil)
        @csv_data = csv_data
        @zip_file = zip_file
      end

      # Count total file references in CSV
      #
      # @return [Integer] Number of rows with file references
      def count_references
        @csv_data.count { |item| item[:file].present? }
      end

      # Find files referenced in CSV but missing from zip
      #
      # @return [Array<String>] Array of missing file names
      def missing_files
        return [] unless @zip_file

        referenced_files - zip_file_list
      end

      # Count files that are both referenced in CSV and found in zip
      #
      # @return [Integer] Number of files found
      def found_files_count
        return 0 unless @zip_file

        (referenced_files & zip_file_list).count
      end

      # Check if zip file was provided
      #
      # @return [Boolean] True if zip file is present
      def zip_included?
        @zip_file.present?
      end

      private

      # Get all file references from CSV data
      #
      # @return [Array<String>] Array of referenced file names (basename only, no paths)
      def referenced_files
        @referenced_files ||= @csv_data.map { |item| File.basename(item[:file]) if item[:file].present? }.compact
      end

      # Get list of files in the zip archive
      #
      # @return [Array<String>] Array of file names in zip (basename only, no paths)
      def zip_file_list
        @zip_file_list ||= begin
          return [] unless @zip_file

          zip_path = @zip_file.respond_to?(:path) ? @zip_file.path : @zip_file
          Zip::File.open(zip_path) do |zip|
            zip.entries.select(&:file?).map { |entry| File.basename(entry.name) }
          end
                           rescue StandardError => e
                             Rails.logger.error("Error reading zip file: #{e.message}")
                             []
        end
      end
    end
  end
end
