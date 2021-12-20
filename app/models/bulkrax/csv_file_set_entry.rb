# frozen_string_literal: true

module Bulkrax
  class CsvFileSetEntry < CsvEntry
    def factory_class
      ::FileSet
    end
  end
end
