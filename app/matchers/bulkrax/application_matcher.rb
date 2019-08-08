require 'language_list'

module Bulkrax
  class ApplicationMatcher
    attr_accessor :to, :from, :parsed, :if, :split, :excluded

    def initialize(args)
      args.each do |k, v|
        send("#{k}=", v)
      end
    end

    def result(parser, content)
      return nil if self.excluded == true || Bulkrax.reserved_properties.include?(self.to)
      return nil if self.if && (!self.if.is_a?(Array) && self.if.length != 2)

      if self.if
        return unless content.send(self.if[0], Regexp.new(self.if[1]))
      end

      @result = content.gsub(/\s/, ' ') # remove any line feeds and tabs
      @result.strip!

      if self.split.is_a?(TrueClass)
        @result = @result.split(/\s*[:;|]\s*/) # default split by : ; |
      elsif self.split
        @result = @result.split(Regexp.new(self.split))
      end

      if @result.is_a?(Array) && @result.size == 1
        @result = @result[0]
      end

      if @result.is_a?(Array) && self.parsed && self.respond_to?("parse_#{to}")
        @result.each_with_index do |res, index|
          @result[index] = send("parse_#{to}", res.strip)
        end
        @result.delete_if { |k, v| v.nil? }
      elsif self.parsed && self.respond_to?("parse_#{to}")
        @result = send("parse_#{to}", @result)
      end

      return @result
    end

    def parse_remote_files(src)
      { url: src.strip } if src.present?
    end

    def parse_language(src)
      l = ::LanguageList::LanguageInfo.find(src.strip)
      l ? l.name : src
    end

    def parse_subject(src)
      string = src.to_s.strip
      if string.present?
        string.slice(0,1).capitalize + string.slice(1..-1)
      end
    end

    def parse_types(src)
      src.to_s.strip.titleize
    end

    # Only add valid resource types
    def parse_resource_type(src)
      Hyrax::ResourceTypesService.label(src.to_s.strip.titleize)
    end

    def parse_format_original(src)
      string = src.to_s.strip
      if string.present?
        string.slice(0,1).capitalize + string.slice(1..-1)
      end
    end

    def parse_format_digital(src)
      case src.to_s.strip.downcase
      when 'application/pdf', 'pdf'
        'PDF'
      when 'image/jpeg', 'image/jpg', 'jpeg', 'jpg'
        'JPEG'
      when 'image/tiff', 'image/tif', 'tiff', 'tif'
        'TIFF'
      when 'image/jp2', 'jp2'
        'JP2'
      when 'image/png', 'png'
        'PNG'
      when 'image/gif', 'gif'
        'GIF'
      when 'video/mp4', 'mp4'
        'MP4'
      when 'video/ogg', 'ogg'
        'OGG'
      when 'video/vnd.avi', 'video/avi', 'avi'
        'AVI'
      when 'audio/aac', 'aac'
        'AAC'
      when 'audio/mpeg', 'audio/mp3', 'audio/mpeg3', 'mpeg', 'mp3', 'mpeg3'
        'MPEG'
      when 'audio/aiff', 'aiff'
        'AIFF'
      when 'audio/webm', 'webm'
        'WEBM'
      when 'audio/wav', 'wav'
        'WAV'
      when 'text/csv', 'csv'
        'CSV'
      when 'text/html', 'html'
        'HTML'
      when 'text/rtf', 'rtf'
        'RTF'
      when 'url'
        'URL'
      else
        nil
      end
    end

  end
end
