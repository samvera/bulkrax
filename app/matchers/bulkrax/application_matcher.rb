module Bulkrax
  class ApplicationMatcher
    attr_accessor :to, :from, :parsed, :if, :split

    def initialize(args)
      args.each do |k, v|
        send("#{k}=", v)
      end
    end

    def result(parser, content)
      return nil if self.if && !self.if.call(parser, content)

      @result = content.gsub(/\s/, ' ') # remove any line feeds and tabs

      if self.split.is_a?(Regexp)
        @result = @result.split(self.split)
      elsif self.split
        @result = @result.split(/\s*[:;|]\s*/) # default split by : ; |
      end

      if @result.is_a?(Array) && @result.size == 1
        @result = @result[0]
      end

      if @result.is_a?(Array) && self.parsed
        @result.each_with_index do |res, index|
          @result[index] = send("parse_#{to}", res)
        end
      elsif self.parsed
        @result = send("parse_#{to}", @result)
      end

      return @result
    end
  end
end
