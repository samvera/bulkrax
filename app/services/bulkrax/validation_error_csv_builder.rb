# frozen_string_literal: true

require 'csv'

module Bulkrax
  # Builds a CSV string containing all validation errors from a guided import.
  # File-level errors (missing required columns, unrecognized headers, empty
  # columns, missing files) appear first as summary rows with a blank `row`
  # cell. Row-level errors follow, one output row per errored data row.
  #
  # Usage:
  #   csv = Bulkrax::ValidationErrorCsvBuilder.build(
  #     headers:     result[:headers],
  #     csv_data:    result[:raw_csv_data],
  #     row_errors:  result[:rowErrors],
  #     file_errors: {
  #       missing_required: result[:missingRequired],
  #       unrecognized:     result[:unrecognized],
  #       empty_columns:    result[:emptyColumns],
  #       missing_files:    result[:missingFiles]
  #     }
  #   )
  class ValidationErrorCsvBuilder
    # @param headers [Array<String>] original CSV headers in order
    # @param csv_data [Array<Hash>] one entry per data row; each hash has
    #   :raw_row (String-keyed hash of column=>value)
    # @param row_errors [Array<Hash>] each hash has :row (Integer) and :message (String)
    # @param file_errors [Hash] file-level issues:
    #   - :missing_required [Array<Hash>] each hash has :model and :field
    #   - :unrecognized [Hash] column_name => suggestion_or_nil
    #   - :empty_columns [Array<Integer>] 1-based column positions with no header
    #   - :missing_files [Array<String>] filenames referenced but not found
    # @return [String] CSV content
    def self.build(headers:, csv_data:, row_errors:, file_errors: {})
      new(headers: headers, csv_data: csv_data, row_errors: row_errors, file_errors: file_errors).build
    end

    def initialize(headers:, csv_data:, row_errors:, file_errors:)
      @headers    = headers
      @csv_data   = csv_data
      @row_errors = row_errors
      @file_errors = file_errors
    end

    def build
      errors_by_row = group_errors_by_row
      blank_data    = Array.new(@headers.length)

      CSV.generate(force_quotes: false) do |csv|
        csv << ['row', 'errors'] + @headers

        file_level_error_rows.each do |message|
          csv << [nil, message] + blank_data
        end

        @csv_data.each_with_index do |record, index|
          row_number = index + 2 # header is row 1; first data row is row 2
          error_messages = errors_by_row[row_number]&.map { |e| e[:message] }&.join(' | ')
          raw_row = record[:raw_row] || {}
          csv << [row_number, error_messages] + @headers.map { |h| raw_row[h] }
        end
      end
    end

    private

    def group_errors_by_row
      @row_errors.each_with_object({}) do |error, hash|
        row_num = error[:row]
        hash[row_num] ||= []
        hash[row_num] << error
      end
    end

    def file_level_error_rows
      messages = []

      Array(@file_errors[:missing_required]).each do |entry|
        messages << "Missing required column '#{entry[:field]}' (#{entry[:model]})"
      end

      Hash(@file_errors[:unrecognized]).each do |col, suggestion|
        msg = "Unrecognized column '#{col}'"
        msg += " (did you mean '#{suggestion}'?)" if suggestion.present?
        messages << msg
      end

      Array(@file_errors[:empty_columns]).each do |pos|
        messages << "Column #{pos + 2} has no header and will be ignored during import"
      end

      Array(@file_errors[:missing_files]).each do |filename|
        messages << "Missing file: #{filename}"
      end

      messages
    end
  end
end
