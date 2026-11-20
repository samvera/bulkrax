# frozen_string_literal: true

module Bulkrax
  # The column and message for each problem ObjectFactoryInterface.visibility_problem
  # reports, shared by import and guided validation so both describe a row alike.
  module VisibilityProblem
    COLUMNS = {
      unknown_visibility: 'visibility',
      unknown_collection_visibility: 'visibility',
      unknown_visibility_during_embargo: 'visibility_during_embargo',
      past_embargo_date: 'embargo_release_date',
      invalid_embargo_date: 'embargo_release_date',
      unknown_visibility_during_lease: 'visibility_during_lease',
      past_lease_date: 'lease_expiration_date',
      invalid_lease_date: 'lease_expiration_date'
    }.freeze

    def self.column(problem)
      COLUMNS.fetch(problem)
    end

    def self.value(problem, attributes)
      attributes.with_indifferent_access[column(problem)].to_s
    end

    def self.message(problem, attributes)
      I18n.t("#{scope(problem)}.message", value: value(problem, attributes))
    end

    def self.suggestion(problem)
      I18n.t("#{scope(problem)}.suggestion")
    end

    def self.scope(problem)
      "bulkrax.importer.guided_import.validation.visibility_validator.errors.#{problem}"
    end
    private_class_method :scope
  end
end
