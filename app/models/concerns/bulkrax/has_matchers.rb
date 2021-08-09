# frozen_string_literal: true

# TODO(alishaevn): see if these rules can be adhered to, instead of disabled
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/ParameterLists
# rubocop:disable Metrics/CyclomaticComplexity

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

          parsed_metadata[object_name] ||= object_multiple ? [{}] : {}
        end

        if matcher
          matched_metadata?(matcher, multiple, name, index, node_content, object_name, object_multiple)
        elsif multiple
          Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")
          multiple_metadata?(name, node_name, node_content, object_name)
        else
          Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")

          node_content = node_content.content if node_content.is_a?(Nokogiri::XML::NodeSet)
          next parsed_metadata[object_name][name] = Array.wrap(node_content.to_s.strip).join('; ') if object_name && node_content
          parsed_metadata[name] = Array.wrap(node_content.to_s.strip).join('; ') if node_content
        end
      end
    end

    def field_supported?(field)
      field = field.gsub('_attributes', '')

      return false if excluded?(field)
      return true if ['collections', 'file', 'remote_files', 'model', 'delete'].include?(field)
      return factory_class.method_defined?(field) && factory_class.properties[field].present?
    end

    def multiple?(field)
      return true if field == 'file' || field == 'remote_files' || field == 'collections'
      return false if field == 'model'

      field_supported?(field) && factory_class&.properties&.[](field)&.[]('multiple')
    end

    def get_object_name(field)
      mapping&.[](field)&.[]('object')
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
      return false unless mapping[field].present?
      mapping[field]['excluded'] || false
    end

    def multiple_metadata?(name, node_name, node_content, object_name)
      Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")
      node_content = node_content.content if node_content.is_a?(Nokogiri::XML::NodeSet)

      if object_name
        parsed_metadata[object_name][name] ||= []
        parsed_metadata[object_name][name] += node_content.is_a?(Array) ? node_content : Array.wrap(node_content.strip)
      else
        parsed_metadata[name] ||= []
        parsed_metadata[name] += node_content.is_a?(Array) ? node_content : Array.wrap(node_content.strip)
      end
    end

    def matched_metadata?(matcher, multiple, name, index, node_content, object_name, object_multiple)
      result = matcher.result(self, node_content)
      return unless result

      if object_name
        if object_multiple
          parsed_metadata[object_name][index] = {} unless parsed_metadata[object_name][index]

          if mapping[name]['nested_type'] && mapping[name]['nested_type'] == 'Array'
            parsed_metadata[object_name][index][name] ||= []
            parsed_metadata[object_name][index][name] += Array.wrap(result)
          else
            parsed_metadata[object_name][index][name] = Array.wrap(result).join('; ')
          end
        elsif multiple
          parsed_metadata[object_name][name] ||= []
          parsed_metadata[object_name][name] += Array.wrap(result)
        else
          parsed_metadata[object_name][name] = Array.wrap(result).join('; ')
        end
      elsif multiple
        parsed_metadata[name] ||= []
        parsed_metadata[name] += Array.wrap(result)
      else
        parsed_metadata[name] = Array.wrap(result).join('; ')
      end
    end
  end
end

# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/ParameterLists
# rubocop:enable Metrics/CyclomaticComplexity
