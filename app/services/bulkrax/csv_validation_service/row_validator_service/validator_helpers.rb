# frozen_string_literal: true

module Bulkrax
  module CsvValidationService::RowValidatorService::ValidatorHelpers
    def each_row
      csv_data.each_with_index do |row, index|
        yield(row, index + 2)
      end
    end
  end
end
