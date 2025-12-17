# frozen_string_literal: true

module Bulkrax
  # Formats split pattern descriptions
  class SampleCsvService::SplitFormatter
    def format(split_value)
      return "Property does not split." if split_value.nil?

      if split_value == true
        parse_pattern(Bulkrax.multi_value_element_split_on.source)
      elsif split_value.is_a?(String)
        parse_pattern(split_value)
      else
        split_value
      end
    end

    private

    def parse_pattern(pattern)
      chars = extract_characters(pattern)
      format_message(chars)
    end

    def extract_characters(pattern)
      if (match = pattern.match(/\[([^\]]+)\]/))
        match[1]
      elsif (single = pattern.match(/\\(.)/))
        single[1]
      else
        pattern
      end
    end

    def format_message(chars)
      formatted = chars.chars.then do |c|
        c.length > 1 ? "#{c[0..-2].join(', ')}, or #{c.last}" : c.first
      end
      "Split multiple values with #{formatted}"
    end
  end
end
