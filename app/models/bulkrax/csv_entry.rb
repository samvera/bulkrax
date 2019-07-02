require 'csv'

module Bulkrax
  class CsvEntry < Entry
    include Bulkrax::Concerns::HasMatchers

    serialize :raw_metadata, JSON

    matcher 'contributor', split: true
    matcher 'creator', split: true
    matcher 'date', split: true
    matcher 'description'
    matcher 'format_digital', parsed: true
    matcher 'format_original', parsed: true
    matcher 'identifier'
    matcher 'language', parsed: true, split: true
    matcher 'place'
    matcher 'publisher', split: true
    matcher 'rights_statement'
    matcher 'subject', split: true
    matcher 'title'
    matcher 'alternative_title'
    matcher 'types', from: %w[types type], split: true, parsed: true
    matcher 'file', split: true

    def build_metadata
      self.parsed_metadata = {}

      if record.nil?
        raise StandardError, 'Record not found'
      elsif required_elements?(record.keys) == false
        raise StandardError, "Missing required elements, required elements are: #{required_elements.join(', ')}"
      end

      record.each do |key, value|
        add_metadata(key, value)
      end
      add_visibility
      add_rights_statement

      parsed_metadata
    end

    def record
      @record ||= raw_metadata
    end

    def matcher_class
      Bulkrax::CsvMatcher
    end

    def required_elements?(keys)
      !required_elements.map { |el| keys.include?(el) }.include?(false)
    end

    def required_elements
      %w[title identifier]
    end
  end
end
