# frozen_string_literal: true

module Bulkrax
  class CsvValidationService
    def self.validate(files)
      new(files).validate
    end

    def initialize(files)
      @files = files
    end

    def validate
      true
    end
  end
end
