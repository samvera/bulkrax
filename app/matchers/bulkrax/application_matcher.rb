# frozen_string_literal: true

require 'language_list'

module Bulkrax
  class ApplicationMatcher
    attr_accessor :to, :from, :parsed, :if, :split, :excluded

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

      @result = content.to_s.gsub(/\s/, ' ') # remove any line feeds and tabs
      @result.strip!
      process_split
      @result = @result[0] if @result.is_a?(Array) && @result.size == 1
      process_parse
      return @result
    end

    def process_split
      if self.split.is_a?(TrueClass)
        @result = @result.split(/\s*[:;|]\s*/) # default split by : ; |
      elsif self.split
        result = @result.split(Regexp.new(self.split))
        @result = result.map(&:strip)
      end
    end

    def process_parse
      if @result.is_a?(Array) && self.parsed && self.respond_to?("parse_#{to}")
        @result.each_with_index do |res, index|
          @result[index] = send("parse_#{to}", res.strip)
        end
        @result.delete(nil)
      elsif self.parsed && self.respond_to?("parse_#{to}")
        @result = send("parse_#{to}", @result)
      end
    end

    def parse_remote_files(src)
      { url: src.strip } if src.present?
    end

    def parse_language(src)
      l = ::LanguageList::LanguageInfo.find(src.strip)
      l ? l.name : src
    end

    def parse_subject(src)
      string = src.to_s.strip.downcase
      return unless string.present?

      string.slice(0, 1).capitalize + string.slice(1..-1)
    end

    def parse_types(src)
      src.to_s.strip.titleize
    end

    # Allow for mapping a model field to the work type or collection
    def parse_model(src)
      model = nil
      if src.is_a?(Array)
        models = src.map { |m| extract_model(m) }.compact
        model = models.first unless models.blank?
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
      Hyrax::ResourceTypesService.label(src.to_s.strip.titleize)
    rescue KeyError
      nil
    end

    def parse_format_original(src)
      # drop the case completely then upcase the first letter
      string = src.to_s.strip.downcase
      return unless string.present?

      string.slice(0, 1).capitalize + string.slice(1..-1)
    end
  end
end
