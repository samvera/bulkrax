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
          parsed_metadata[object_name] ||= object_multiple ? [{}] : {}
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

        # binding.pry if name == 'format'
        object_name.present? ? set_parsed_object_data(object_multiple, object_name, name, index, value) : set_parsed_data(name, value)
      end
    end

    def set_parsed_data(name, value)
      return parsed_metadata[name] = value unless multiple?(name)

      parsed_metadata[name] ||= []
      parsed_metadata[name] += Array.wrap(value).flatten
    end

    def set_parsed_object_data(object_multiple, object_name, name, index, value)
      if object_multiple
        index ||= 0
        parsed_metadata[object_name][index] ||= {}
        parsed_metadata[object_name][index][name] ||= []
        if value.is_a?(Array)
          parsed_metadata[object_name][index][name] += value
        else
          parsed_metadata[object_name][index][name] = value
        end
      else
        parsed_metadata[object_name][name] ||= []
        if value.is_a?(Array)
          parsed_metadata[object_name][name] += value
        else
          parsed_metadata[object_name][name] = value
        end
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
      return factory_class.method_defined?(field) && factory_class.properties[field].present?
    end

    def supported_bulkrax_fields
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      @supported_bulkrax_fields ||=
        %W[
          id
          file
          remote_files
          model
          delete
          #{parser.collection_field_mapping}
          #{related_parents_parsed_mapping}
          #{related_children_parsed_mapping}
        ]
    end

    def multiple?(field)
      ActiveSupport::Deprecation.warn(
        'Creating Collections using the collection_field_mapping will no longer be supported as of Bulkrax version 3.0.' \
        ' Please configure Bulkrax to use related_parents_field_mapping and related_children_field_mapping instead.'
      )
      @multiple_bulkrax_fields ||=
        %W[
          file
          remote_files
          #{parser.collection_field_mapping}
          #{related_parents_parsed_mapping}
          #{related_children_parsed_mapping}
        ]
        binding.pry if field == 'format'

      return true if @multiple_bulkrax_fields.include?(field)
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
      return false if mapping[field].blank?
      mapping[field]['excluded'] || false
    end
  end
end
# rubocop:enable Metrics/ModuleLength
