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

      def matcher(name, args={})
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

      field_to(node_name).each do | name |
        next unless field_supported?(name)
        matcher = self.class.matcher(name, mapping[name].symbolize_keys) if mapping[name]

        if matcher
          result = matcher.result(self, node_content)
          if result
            parsed_metadata[name] ||= []

            if result.is_a?(Array)
              parsed_metadata[name] += result
            else
              parsed_metadata[name] << result
            end
          end
        else
          # we didn't find a match, add by default
          parsed_metadata[name] ||= []
          parsed_metadata[name] << node_content.strip
        end
      end
    end

    def field_supported?(field)
      factory_class.method_defined?(field) || field == 'file' || field == 'remote_files'
    end

    # Hyrax field to use for the given import field
    # @param field [String] the importer field name
    # @return [Array] hyrax fields
    def field_to(field)
      fields = mapping&.map { |key, value|
        key if (value['from'] && value['from'].include?(field)) || key == field
      }&.compact
      fields = nil if fields.blank?
      return fields || [field]
    end
  end
end
