# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Reports a file set row listing more files than its import takes, by asking
    # the object factory the question import asks
    # (ObjectFactoryInterface.file_set_row_problem).
    module FileSetFiles
      SCOPE = 'bulkrax.importer.guided_import.validation.file_set_files_validator.errors'

      def self.call(record, row_index, context)
        return if record[:deleting]
        return unless Bulkrax::FactoryClassFinder.resolve(record[:model].presence || Bulkrax.default_work_type) == Bulkrax.file_model_class

        file_count = %w[file remote_files].sum { |field| Bulkrax::FieldResolver.row_values(record[:raw_row], context[:mappings], field, parse: false).size }
        problem = Bulkrax.object_factory.file_set_row_problem(file_count: file_count)
        return unless problem

        context[:errors] << {
          row: row_index,
          source_identifier: record[:source_identifier],
          severity: 'error',
          category: problem.to_s,
          column: 'file',
          value: file_count.to_s,
          message: I18n.t("#{SCOPE}.#{problem}.message", value: file_count),
          suggestion: I18n.t("#{SCOPE}.#{problem}.suggestion")
        }
      end
    end
  end
end
