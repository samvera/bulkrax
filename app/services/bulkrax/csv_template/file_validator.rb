# frozen_string_literal: true

module Bulkrax
  module CsvTemplate
    ##
    # Validates file references in CSV against zip archive contents
    class FileValidator
      attr_reader :csv_data, :zip_file

      def initialize(csv_data, zip_file = nil, admin_set_id = nil)
        @csv_data = csv_data
        @zip_file = zip_file
        @admin_set_id = admin_set_id
      end

      def count_references
        @csv_data.count { |item| item[:file].present? }
      end

      def missing_files
        return [] unless @zip_file

        referenced_files - zip_file_list
      end

      def found_files_count
        return 0 unless @zip_file

        (referenced_files & zip_file_list).count
      end

      def zip_included?
        @zip_file.present?
      end

      def possible_missing_files?
        return false unless referenced_files.any?
        return true if @zip_file.blank?

        false
      end

      private

      def referenced_files
        @referenced_files ||= @csv_data.flat_map do |item|
          next [] if item[:file].blank?

          item[:file].split(Bulkrax::CsvParser.file_split_pattern).map { |f| File.basename(f.strip) }
        end.compact
      end

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
