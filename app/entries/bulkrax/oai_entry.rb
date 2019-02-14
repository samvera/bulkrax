module Bulkrax
  class OaiEntry < ApplicationEntry
    def entry_class
      Work
    end

    def raw_record
      @raw_record ||= client.get_record({identifier: identifier})
    end

  end
end
