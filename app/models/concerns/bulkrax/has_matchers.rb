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
          excluded: args[:excluded]
        )
        self.matchers[name] = matcher
      end
    end

    def add_metadata(node_name, node_content)
      field_to(node_name).each do |name|
        matcher = self.class.matcher(name, mapping[name].symbolize_keys) if mapping[name] # the field matched to a pre parsed value in application_matcher.rb
        object = object_name(name) || false # the field is an object of key:value pairs. e.g. { obj: { key: value }}
        multiple = multiple?(name) # the field has multiple values. e.g. ['a', 'b', 'c']
        object_multiple = object && multiple?(object) # the field is an array of objects

        next unless field_supported?(name) || (object && field_supported?(object))

        if object
          Rails.logger.info("Bulkrax Column automatically matched object #{node_name}, #{node_content}")

          parsed_metadata[object] ||= object_multiple ? [{}] : {}
        end

        if matcher
          matched_metadata?(matcher, multiple, name, node_content, object, object_multiple)
        elsif multiple
          Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")
          multiple_metadata?(name, node_name, node_content, object)
        else
          Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")

          node_content = node_content.content if node_content.is_a?(Nokogiri::XML::NodeSet)
          next parsed_metadata[object][name] = Array.wrap(node_content.to_s.strip).join('; ') if object && node_content
          parsed_metadata[name] = Array.wrap(node_content.to_s.strip).join('; ') if node_content
        end
      end
    end

    def field_supported?(field)
      field = field.gsub('_attributes', '')

      return false if excluded?(field)
      return true if ['file', 'remote_files', 'model', 'delete'].include?(field)
      return factory_class.method_defined?(field) && factory_class.properties[field].present?
    end

    def multiple?(field)
      return true if field == 'file' || field == 'remote_files'
      return false if field == 'model'

      field_supported?(field) && factory_class&.properties&.[](field)&.[]('multiple')
    end

    def object_name(field)
      mapping&.[](field)&.[]('object')
    end

    # Hyrax field to use for the given import field
    # @param field [String] the importer field name
    # @return [Array] hyrax fields
    def field_to(field)
      fields = mapping&.map do |key, value|
        value['from'] = value['from'].join(', ') if value['from'].instance_of?(Array)

        key if (value.present? && value['from']&.include?(field)) || key == field
      end&.compact

      return [field] if fields.blank?
      return fields
    end

    # Check whether a field is explicitly excluded in the mapping
    def excluded?(field)
      return false unless mapping[field].present?
      mapping[field]['excluded'] || false
    end

    def multiple_metadata?(name, node_name, node_content, object)
      Rails.logger.info("Bulkrax Column automatically matched #{node_name}, #{node_content}")
      node_content = node_content.content if node_content.is_a?(Nokogiri::XML::NodeSet)

      if object
        parsed_metadata[object][name] ||= []
        parsed_metadata[object][name] += node_content.is_a?(Array) ? node_content : Array.wrap(node_content.strip)
      else
        parsed_metadata[name] ||= []
        parsed_metadata[name] += node_content.is_a?(Array) ? node_content : Array.wrap(node_content.strip)
      end
    end

    def matched_metadata?(matcher, multiple, name, node_content, object, object_multiple)
      result = matcher.result(self, node_content)
      return unless result

      if object
        if object_multiple
          # find the index of the first object in the `object` array where the `name` key doesn't already exist
          index = parsed_metadata[object].find_index { |obj| obj[name].nil? }

          if index.nil?
            # if all existing objects have our `name` key in it already
            # push a new object to the end of the array and add the `result` to it
            parsed_metadata[object] << {}
            parsed_metadata[object][parsed_metadata[object].length - 1][name] = Array.wrap(result).join('; ')
          else
            # if an object already exists that doesn't have our `name` key in it, add the `result` to that object
            parsed_metadata[object][index][name] = Array.wrap(result).join('; ')
          end
        elsif multiple
          parsed_metadata[object][name] ||= []
          parsed_metadata[object][name] += Array.wrap(result)
        else
          parsed_metadata[object][name] = Array.wrap(result).join('; ')
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
