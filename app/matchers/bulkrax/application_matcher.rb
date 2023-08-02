# frozen_string_literal: true

require 'language_list'

module Bulkrax
  class ApplicationMatcher
    attr_accessor :to, :from, :parsed, :if, :split, :excluded, :nested_type

    # New parse methods will need to be added here; you'll also want to define a corresponding
    # "parse_#{field}" method.
    class_attribute :parsed_fields, instance_writer: false, default: ['remote_files', 'language', 'subject', 'types', 'model', 'resource_type', 'format_original']

    def initialize(args)
      args.each do |k, v|
        send("#{k}=", v)
      end
    end

    def result(_parser, content)
      return nil if self.excluded == true || Bulkrax.reserved_properties.include?(self.to)
      return nil if self.if && (!self.if.is_a?(Array) && self.if.length != 2)

      if self.if
        return unless content.send(self.if[0], Regexp.new(self.if[1]))
      end

      # @result will evaluate to an empty string for nil content values
      @result = content.to_s.gsub(/\s/, ' ').strip # remove any line feeds and tabs
      # blank needs to be based to split, only skip nil
      process_split unless @result.nil?
      @result = @result[0] if @result.is_a?(Array) && @result.size == 1
      process_parse
      return @result
    end

    def process_split
      if self.split.is_a?(TrueClass)
        @result = @result.split(Bulkrax.multi_value_element_split_on)
      elsif self.split
        @result = @result.split(Regexp.new(self.split))
        @result = @result.map(&:strip).select(&:present?)
      end
    end

    def process_parse
      # This accounts for prefixed matchers
      parser = parsed_fields.find { |field| to&.include? field }

      if @result.is_a?(Array) && self.parsed && self.respond_to?("parse_#{parser}")
        @result.each_with_index do |res, index|
          @result[index] = send("parse_#{parser}", res.strip)
        end
        @result.delete(nil)
      elsif self.parsed && self.respond_to?("parse_#{parser}")
        @result = send("parse_#{parser}", @result)
      end
    end

    def parse_remote_files(src)
      return if src.blank?
      src.strip!
      name = Bulkrax::Importer.safe_uri_filename(src)
      { url: src, file_name: name }
    end

    def parse_language(src)
      l = ::LanguageList::LanguageInfo.find(src.strip)
      l ? l.name : src
    end

    def parse_subject(src)
      string = src.strip.downcase
      return if string.blank?

      string.slice(0, 1).capitalize + string.slice(1..-1)
    end

    def parse_types(src)
      src.strip.titleize
    end

    # Allow for mapping a model field to the work type or collection
    def parse_model(src)
      model = nil
      if src.is_a?(Array)
        models = src.map { |m| extract_model(m) }.compact
        model = models.first if models.present?
      else
        model = extract_model(src)
      end
      return model
    end

    def extract_model(src)
      if src&.match(URI::ABS_URI)
        src.split('/').last
      else
        src
      end
    rescue StandardError
      nil
    end

    # Only add valid resource types
    def parse_resource_type(src)
      ActiveSupport::Deprecation.warn('#parse_resource_type will be removed in Bulkrax v6.0.0')
      Hyrax::ResourceTypesService.label(src.to_s.strip.titleize)
    rescue KeyError
      nil
    end

    def parse_format_original(src)
      # drop the case completely then upcase the first letter
      string = src.to_s.strip.downcase
      return if string.blank?

      string.slice(0, 1).capitalize + string.slice(1..-1)
    end
  end
end
