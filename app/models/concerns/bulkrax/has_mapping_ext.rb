# frozen_string_literal: true

module Bulkrax
  module HasMappingExt
    ##
    # Field of the model that can be supported
    def field_supported?(field)
      field = field.gsub("_attributes", "")

      return false if excluded?(field)
      return true if supported_bulkrax_fields.include?(field)

      property_defined = factory_class.singleton_methods.include?(:properties) && factory_class.properties[field].present?

      factory_class.method_defined?(field) && (Bulkrax::ValkyrieObjectFactory.schema_properties(factory_class).include?(field) || property_defined)
    end

    ##
    # Determine a multiple properties field
    def multiple?(field)
      @multiple_bulkrax_fields ||=
        %W[
          file
          remote_files
          rights_statement
          #{related_parents_parsed_mapping}
          #{related_children_parsed_mapping}
        ]

      return true if @multiple_bulkrax_fields.include?(field)
      return false if field == "model"

      field_supported?(field) && (multiple_field?(field) || factory_class.singleton_methods.include?(:properties) && factory_class&.properties&.[](field)&.[]("multiple"))
    end

    def multiple_field?(field)
      form_definition = schema_form_definitions[field.to_sym]
      form_definition.nil? ? false : form_definition.multiple?
    end

    # override: we want to directly infer from a property being multiple that we should split when it's a String
    # def multiple_metadata(content)
    #   return unless content

    #   case content
    #   when Nokogiri::XML::NodeSet
    #     content&.content
    #   when Array
    #     content
    #   when Hash
    #     Array.wrap(content)
    #   when String
    #     String(content).strip.split(Bulkrax.multi_value_element_split_on)
    #   else
    #     Array.wrap(content)
    #   end
    # end

    def schema_form_definitions
      @schema_form_definitions ||= ::SchemaLoader.new.form_definitions_for(factory_class.name.underscore.to_sym)
    end
  end
end

[Bulkrax::HasMatchers, Bulkrax::HasMatchers.singleton_class].each do |mod|
  mod.prepend Bulkrax::HasMappingExt
end
