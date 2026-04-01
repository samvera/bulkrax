# frozen_string_literal: true

require 'csv'

module Bulkrax
  # Builds a CSV string containing only the rows from a validated CSV that have
  # row-level errors. An `errors` column is prepended as column 1; multiple
  # errors on the same row are joined with " | ".
  #
  # Usage:
  #   csv = Bulkrax::ValidationErrorCsvBuilder.build(
  #     headers:    result[:headers],
  #     csv_data:   result[:raw_csv_data],
  #     row_errors: result[:rowErrors]
  #   )
  class ValidationErrorCsvBuilder
    # @param headers [Array<String>] original CSV headers in order
    # @param csv_data [Array<Hash>] one entry per data row; each hash must have
    #   :row_number (Integer, 1-indexed data row, so first data row == 2 matching
    #   validator convention) and :raw_row (String-keyed hash of column=>value)
    # @param row_errors [Array<Hash>] each hash has :row (Integer) and :message (String)
    # @return [String] CSV content
    def self.build(headers:, csv_data:, row_errors:)
      new(headers: headers, csv_data: csv_data, row_errors: row_errors).build
    end

    def initialize(headers:, csv_data:, row_errors:)
      @headers    = headers
      @csv_data   = csv_data
      @row_errors = row_errors
    end

    def build
      errors_by_row = group_errors_by_row

      CSV.generate(force_quotes: false) do |csv|
        csv << ['row', 'errors'] + @headers

        @csv_data.each_with_index do |record, index|
          row_number = index + 2 # header is row 1; first data row is row 2
          next unless errors_by_row.key?(row_number)

          error_messages = errors_by_row[row_number].map { |e| e[:message] }.join(' | ')
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
  end
end
