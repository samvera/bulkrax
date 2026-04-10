# frozen_string_literal: true

# Helpers for specs that use PostgreSQL-specific features (JSONB operators,
# ::integer casts, date_trunc, jsonb_array_elements_text, etc.).
#
# On PostgreSQL, specs run normally against the real DB.
# On SQLite, the helper auto-stubs the ActiveRecord chain so the specs still
# execute and verify the aggregator's interface and return shape via mocks.
#
# Usage in specs:
#   before { stub_postgres_scope(:funnel, { 1 => 2, 2 => 1 }) }
module DatabaseHelpers
  def self.postgres?
    ActiveRecord::Base.connection.adapter_name.downcase.include?('postgresql')
  end

  # Builds a stub AR relation that responds to common query chain methods.
  # On Postgres this is a no-op — the real query runs.
  # On SQLite this intercepts before Postgres-specific SQL reaches the adapter.
  #
  # @param scope_name [Symbol] the ImportMetric scope to stub (:funnel, :validations, etc.)
  # @param result [Object] the value to return from the terminal method (count, average, pluck, etc.)
  # @return [RSpec::Mocks::Double, nil] the stubbed relation, or nil on Postgres
  def stub_postgres_scope(scope_name, result)
    return if DatabaseHelpers.postgres?

    relation = build_chainable_relation
    allow(Bulkrax::ImportMetric).to receive(scope_name).and_return(relation)
    attach_terminal_method(relation, result)
    relation
  end

  # Stubs ImportMetric.find_by_sql for raw SQL queries on SQLite.
  def stub_postgres_find_by_sql(result)
    return if DatabaseHelpers.postgres?

    allow(Bulkrax::ImportMetric).to receive(:find_by_sql).and_return(result)
  end

  private

  def build_chainable_relation
    relation = double('ImportMetric::Relation') # rubocop:disable RSpec/VerifiedDoubles
    %i[in_range where group order limit includes joins].each do |method|
      allow(relation).to receive(method).and_return(relation)
    end
    relation
  end

  def attach_terminal_method(relation, result)
    case result
    when Hash, Integer
      allow(relation).to receive(:count).and_return(result)
    when BigDecimal
      allow(relation).to receive(:average).and_return(result)
    when Array
      allow(relation).to receive(:pluck).and_return(result)
    when nil
      allow(relation).to receive(:average).and_return(nil)
      allow(relation).to receive(:count).and_return(0)
    end
  end
end

RSpec.configure do |config|
  config.include DatabaseHelpers
end
