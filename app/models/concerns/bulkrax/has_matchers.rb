# frozen_string_literal: true
# rubocop:disable Metrics/ModuleLength
module Bulkrax
  module HasMatchers
    extend ActiveSupport::Concern

    included do
      class_attribute :matchers
      self.matchers ||= {}
    end

    class_methods do
      def matcher_class
        Bulkrax::ApplicationMatcher
      end

      def matcher(name, args = {})
        matcher = matcher_class.new(
          to: name,
          parsed: args[:parsed],
          split: args[:split],
          if: args[:if],
          excluded: args[:excluded],
          nested_type: args[:nested_type]
        )
        self.matchers[name] = matcher
      end
    end

    def add_metadata(node_name, node_content, index = nil)
      field_to(node_name).each do |name|
        matcher = self.class.matcher(name, mapping[name].symbolize_keys) if mapping[name] # the field matched to a pre parsed value in application_matcher.rb
        object_name = get_object_name(name) || false # the "key" of an object property. e.g. { object_name: { alpha: 'beta' } }
        multiple = multiple?(name) # the property has multiple values. e.g. 'letters': ['a', 'b', 'c']
        object_multiple = object_name && multiple?(object_name) # the property's value is an array of object(s)

        next unless field_supported?(name) || (object_name && field_supported?(object_name))

        if object_name
          Rails.logger.info("Bulkrax Column automatically matched object #{node_name}, #{node_content}")
          init_object_container(object_name, object_multiple)
        end

        value = if matcher
                  result = matcher.result(self, node_content)
                  matched_metadata(multiple, name, result, object_multiple)
                elsif multiple
                  Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")
                  multiple_metadata(node_content)
                else
                  Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")
                  single_metadata(node_content)
                end

        object_name.present? ? set_parsed_object_data(object_multiple, object_name, name, index, value) : set_parsed_data(name, value)
      end
    end

    def get_object_name(field)
      mapping&.[](field)&.[]('object')
    end

    # When any field-mapping sibling under `object_name` carries
    # `nested_attributes: true`, Bulkrax routes the imported data through
    # `parsed_metadata["#{object_name}_attributes"]` as a numbered-key hash
    # (with `_destroy: 'false'` per row) — the shape consumed by Reform's
    # nested-attributes machinery and other `*_attributes`-style populators.
    def nested_attributes_object?(object_name)
      return false unless mapping.is_a?(Hash) && object_name.present?
      mapping.any? { |_, cfg| cfg.is_a?(Hash) && cfg['object'] == object_name && cfg['nested_attributes'] }
    end

    def parsed_object_target_key(object_name)
      nested_attributes_object?(object_name) ? "#{object_name}_attributes" : object_name
    end

    def init_object_container(object_name, object_multiple)
      target_key = parsed_object_target_key(object_name)
      default = if object_multiple
                  nested_attributes_object?(object_name) ? {} : [{}]
                else
                  {}
                end
      parsed_metadata[target_key] ||= default
    end

    def set_parsed_data(name, value)
      return parsed_metadata[name] = value unless multiple?(name)

      parsed_metadata[name] ||= []
      parsed_metadata[name] += Array.wrap(value).flatten
      parsed_metadata[name].uniq!
    end

    def set_parsed_object_data(object_multiple, object_name, name, index, value)
      target_key = parsed_object_target_key(object_name)
      target = object_target_for(target_key, object_name, object_multiple, index)
      assign_object_value(target, object_row_key(name), value)
    end

    # The key a value is written under inside an `object:` row. Defaults to the
    # mapping key, but a mapping may set `name:` (alias `row_key:`) to use a
    # different in-row key. This lets two mappings with distinct (globally
    # unique) keys both write the same in-row key into different objects — e.g.
    # a `title` sub-property shared by two compounds, each needing a unique
    # top-level mapping key but the same `title` key inside its row.
    def object_row_key(name)
      cfg = mapping[name]
      return name unless cfg.is_a?(Hash)

      cfg['name'] || cfg[:name] || cfg['row_key'] || cfg[:row_key] || name
    end

    # Resolve the hash slot that `name` should be written into, initializing
    # any intermediate containers. Returns the leaf hash so the caller can
    # assign the value with a single statement.
    def object_target_for(target_key, object_name, object_multiple, index)
      return parsed_metadata[target_key] unless object_multiple

      idx = index || 0
      if nested_attributes_object?(object_name)
        parsed_metadata[target_key][idx.to_s] ||= { '_destroy' => 'false' }
        parsed_metadata[target_key][idx.to_s]
      else
        parsed_metadata[target_key][idx] ||= {}
        parsed_metadata[target_key][idx]
      end
    end

    def assign_object_value(target, name, value)
      target[name] ||= []
      if value.is_a?(Array)
        target[name] += value
      else
        target[name] = value
      end
    end

    def single_metadata(content)
      content = content.content if content.is_a?(Nokogiri::XML::NodeSet)
      return unless content
      Array.wrap(content.to_s.strip).join('; ')
    end

    def multiple_metadata(content)
      return unless content

      case content
      when Nokogiri::XML::NodeSet
        content&.content
      when Array
        content
      when Hash
        Array.wrap(content)
      when String
        Array.wrap(content.strip)
      else
        Array.wrap(content)
      end
    end

    def matched_metadata(multiple, name, result, object_multiple)
      if object_multiple
        if mapping[name]['nested_type'] && mapping[name]['nested_type'] == 'Array'
          multiple_metadata(result)
        else
          single_metadata(result)
        end
      elsif multiple
        multiple_metadata(result)
      else
        single_metadata(result)
      end
    end

    def field_supported?(field)
      field = field.gsub('_attributes', '')

      return false if excluded?(field)
      return true if supported_bulkrax_fields.include?(field)

      Bulkrax.object_factory.field_supported?(field: field, model: factory_class, admin_set_id: importerexporter.try(:admin_set_id))
    end

    def supported_bulkrax_fields
      @supported_bulkrax_fields ||= fields_that_are_always_singular +
                                    fields_that_are_always_multiple
    end

    ##
    # Determine a multiple properties field
    def multiple?(field)
      return true if fields_that_are_always_singular.include?(field.to_s)
      return false if fields_that_are_always_multiple.include?(field.to_s)

      Bulkrax.object_factory.field_multi_value?(field: field, model: factory_class, admin_set_id: importerexporter.try(:admin_set_id))
    end

    def fields_that_are_always_multiple
      @fields_that_are_always_multiple = %w[
        id
        delete
        model
        visibility
        visibility_during_embargo
        embargo_release_date
        visibility_after_embargo
        visibility_during_lease
        lease_expiration_date
        visibility_after_lease
      ]
    end

    def fields_that_are_always_singular
      @fields_that_are_always_singular ||= %W[
        file
        remote_files
        rights_statement
        #{related_parents_parsed_mapping}
        #{related_children_parsed_mapping}
      ]
    end

    def schema_form_definitions
      @schema_form_definitions ||= ::SchemaLoader.new.form_definitions_for(factory_class.name.underscore.to_sym)
    end

    # Hyrax field to use for the given import field
    # @param field [String] the importer field name
    # @return [Array] hyrax fields
    def field_to(field)
      fields = mapping&.map do |key, value|
        return unless value

        if value['from'].instance_of?(Array)
          key if value['from'].include?(field) || key == field
        elsif (value['from'] == field) || key == field
          key
        end
      end&.compact

      return [field] if fields.blank?
      return fields
    end

    # Check whether a field is explicitly excluded in the mapping
    def excluded?(field)
      return false if mapping[field].blank?
      mapping[field]['excluded'] || false
    end
  end
end
# rubocop:enable Metrics/ModuleLength
