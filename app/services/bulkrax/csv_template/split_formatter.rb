# frozen_string_literal: true

module Bulkrax
  module CsvTemplate
    # Formats split pattern descriptions
    class SplitFormatter
      def format(split_value)
        return "Property does not split." if split_value.nil?

        if split_value == true
          parse_pattern(Bulkrax.multi_value_element_split_on.source)
        elsif split_value.is_a?(Regexp)
          parse_pattern(split_value.source)
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
        list = chars.chars
        # Use spaces rather than commas between delimiters so the message
        # stays unambiguous when one of the delimiters IS a comma.
        formatted = if list.length <= 1
                      list.first || chars # no extractable chars → surface as-is
                    else
                      "#{list[0..-2].join(' ')} or #{list.last}"
                    end
        "Split multiple values with #{formatted}"
      end
    end
  end
end
