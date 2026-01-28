# frozen_string_literal: true

module SchemaTestHelpers
  # Helper to build a mock field for schema testing
  # @param name [Symbol] the field name
  # @param meta [Hash, nil] the metadata hash
  # @param responds_to_meta [Boolean] whether field.respond_to?(:meta) returns true
  def build_field(name:, meta: nil, responds_to_meta: true)
    field = double("Field_#{name}", name: name)
    allow(field).to receive(:respond_to?).with(:meta).and_return(responds_to_meta)
    allow(field).to receive(:meta).and_return(meta) if responds_to_meta
    field
  end

  # Helper to create a testable class with schema support
  # Uses real Ruby classes instead of mocking singleton_class
  # @param schema [Array, nil] the schema to return
  # @param responds_to_schema [Boolean] whether klass.respond_to?(:schema) returns true
  # @param singleton_returns_nil [Boolean] if true, instance.singleton_class.schema returns nil
  def build_schema_class(schema:, responds_to_schema: true, singleton_returns_nil: false)
    schema_value = schema
    singleton_nil = singleton_returns_nil

    Class.new do
      @schema = schema_value
      @responds_to_schema = responds_to_schema
      @singleton_returns_nil = singleton_nil

      class << self
        attr_accessor :schema, :responds_to_schema, :singleton_returns_nil

        def respond_to?(method, include_all = false)
          return responds_to_schema if method == :schema
          super
        end
      end

      define_method(:initialize) do
        # Define schema on this instance's singleton class
        sc = singleton_nil ? nil : schema_value
        self.singleton_class.define_method(:schema) { sc }
      end
    end
  end
end
