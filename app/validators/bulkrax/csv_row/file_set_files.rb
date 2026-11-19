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

        file_count = file_values(record, context).size
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

      # CsvEntry#add_file splits each file cell even when the mapping sets no split
      def self.file_values(record, context)
        %w[file remote_files].flat_map do |field|
          values = Bulkrax::FieldResolver.row_values(record[:raw_row], context[:mappings], field, parse: false)
          field == 'file' ? values.flat_map { |value| value.split(Bulkrax::CsvParser.file_split_pattern).map(&:strip).reject(&:blank?) } : values
        end
      end
      private_class_method :file_values
    end
  end
end
