# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Reports a row whose visibility, embargo or lease would fail its import, by
    # asking the object factory the question import asks
    # (ObjectFactoryInterface.visibility_problem).
    module Visibility
      def self.call(record, row_index, context)
        return if record[:deleting]

        attributes = visibility_attributes(record, context[:mappings])
        model = record[:model].presence || Bulkrax.default_work_type
        problem = Bulkrax.object_factory.visibility_problem(attributes, model: Bulkrax::FactoryClassFinder.resolve(model)&.to_s || model)
        return unless problem

        context[:errors] << {
          row: row_index,
          source_identifier: record[:source_identifier],
          severity: 'error',
          category: problem.to_s,
          column: VisibilityProblem.column(problem),
          value: VisibilityProblem.value(problem, attributes),
          message: VisibilityProblem.message(problem, attributes),
          suggestion: VisibilityProblem.suggestion(problem)
        }
      end

      def self.visibility_attributes(record, mappings)
        CsvTemplate::ColumnDescriptor::COLUMN_DESCRIPTIONS[:visibility].flat_map(&:keys).each_with_object({}) do |field, attributes|
          _header, value = Bulkrax::FieldResolver.row_value(record[:raw_row], mappings, field)
          attributes[field] = value if value
        end
      end
      private_class_method :visibility_attributes
    end
  end
end
