
# this is a PORO to help pass errors around
module Bulkrax
  class ImportFailed
    attr_accessor :message, :backtrace

    def initialize(message, backtrace)
      @message = message
      @backtrace = backtrace
    end
  end
end
