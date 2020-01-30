# frozen_string_literal: true

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
        next unless field_supported?(name)
        matcher = self.class.matcher(name, mapping[name].symbolize_keys) if mapping[name]
        multiple = multiple?(name)
        if matcher
          result = matcher.result(self, node_content)
          if result
            if multiple
              parsed_metadata[name] ||= []
              parsed_metadata[name] += Array.wrap(result)
            else
              parsed_metadata[name] = Array.wrap(result).join('; ')
            end
          end
        # we didn't find a match, add by default
        elsif multiple
          parsed_metadata[name] ||= []
          parsed_metadata[name] += Array.wrap(node_content.strip)
        else
          parsed_metadata[name] = Array.wrap(node_content.strip).join('; ')
        end
      end
    end

    def field_supported?(field)
      field = field.gsub('_attributes', '')
      (factory_class.method_defined?(field) && !excluded?(field)) || field == 'file' || field == 'remote_files' || field == 'model'
    end

    def multiple?(field)
      return true if field == 'file' || field == 'remote_files'
      return false if field == 'model'
      field_supported?(field) && factory_class.properties[field]['multiple']
    end

    # Hyrax field to use for the given import field
    # @param field [String] the importer field name
    # @return [Array] hyrax fields
    def field_to(field)
      fields = mapping&.map do |key, value|
        key if (value.present? && value['from']&.include?(field)) || key == field
      end&.compact
      fields = nil if fields.blank?
      return fields || [field]
    end

    # Check whether a field is explicitly excluded in the mapping
    def excluded?(field)
      return false unless mapping[field].present?
      mapping[field]['excluded'] || false
    end
  end
end
