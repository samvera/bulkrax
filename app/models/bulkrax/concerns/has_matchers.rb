module Bulkrax::Concerns::HasMatchers
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
      from = args[:from] || [name]

      matcher = matcher_class.new(
        to: name,
        from: from,
        parsed: args[:parsed],
        split: args[:split],
        if: args[:if]
      )

      from.each do |lookup|
        self.matchers[lookup] = matcher
      end
    end
  end

  def add_metadata(node_name, node_content)
    matcher = self.class.matchers[node_name]

    return unless factory_class.method_defined?(node_name.to_sym) || node_name == 'file'

    if matcher
      result = matcher.result(self, node_content)
      if result
        key = matcher.to
        parsed_metadata[key] ||= []

        if result.is_a?(Array)
          parsed_metadata[key] += result
        else
          parsed_metadata[key] << result
        end
      end
    else
      # we didn't find a match, add by default
      parsed_metadata[node_name] ||= []
      parsed_metadata[node_name] << node_content.strip
    end
  end
end
