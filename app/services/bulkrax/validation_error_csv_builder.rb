# frozen_string_literal: true

require 'csv'

module Bulkrax
  # Builds a CSV string containing all validation errors from a guided import.
  #
  # Output columns, in order:
  #   1. row        — 1-based row number from the source CSV (blank for file-level rows)
  #   2. errors     — all error messages for that row, joined with " | "
  #   3. categories — distinct validator categories for that row's errors (e.g.
  #                   "missing_required_value | invalid_parent_reference"),
  #                   joined with " | "; blank for file-level rows
  #   4..N. the original CSV headers, carrying the raw cell values
  #
  # File-level errors (missing required columns, unrecognized headers, empty
  # columns, missing files) appear first as summary rows with a blank `row`
  # and `categories` cell. Row-level errors follow, one output row per data row.
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
    I18N_BASE = 'bulkrax.importer.guided_import.validation.validation_error_csv_builder'
    private_constant :I18N_BASE

    # @param headers [Array<String>] original CSV headers in order
    # @param csv_data [Array<Hash>] one entry per data row; each hash has
    #   :raw_row (String-keyed hash of column=>value)
    # @param row_errors [Array<Hash>] each hash describes a single row-level
    #   validation result with the following keys:
    #   - :row [Integer] 1-based source row number (header is row 1)
    #   - :message [String] human-readable error/warning message
    #   - :category [String, nil] validator category slug used to populate the
    #     `categories` output column (e.g. 'missing_required_value',
    #     'invalid_parent_reference'); omitted/nil categories are dropped
    #   - :severity, :column, :value, :suggestion, :source_identifier — not
    #     emitted by this builder but commonly present on the same hash
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
        csv << ['row', 'errors', 'categories'] + @headers

        file_level_error_rows.each do |message|
          csv << [nil, message, nil] + blank_data
        end

        @csv_data.each_with_index do |record, index|
          row_number = index + 2 # header is row 1; first data row is row 2
          row_errors = errors_by_row[row_number]
          error_messages   = row_errors&.map { |e| e[:message] }&.join(' | ')
          error_categories = row_errors&.map { |e| e[:category] }&.compact&.uniq&.join(' | ')
          raw_row = record[:raw_row] || {}
          csv << [row_number, error_messages, error_categories] + @headers.map { |h| raw_row[h] }
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
        messages << I18n.t("#{I18N_BASE}.missing_required_column", field: entry[:field], model: entry[:model])
      end

      Hash(@file_errors[:unrecognized]).each do |col, suggestion|
        messages << if suggestion.present?
                      I18n.t("#{I18N_BASE}.unrecognized_column_with_suggestion", column: col, suggestion: suggestion)
                    else
                      I18n.t("#{I18N_BASE}.unrecognized_column", column: col)
                    end
      end

      Array(@file_errors[:empty_columns]).each do |pos|
        messages << I18n.t("#{I18N_BASE}.empty_column", column: pos + 2)
      end

      Array(@file_errors[:missing_files]).each do |filename|
        messages << I18n.t("#{I18N_BASE}.missing_file", filename: filename)
      end

      messages
    end
  end
end
