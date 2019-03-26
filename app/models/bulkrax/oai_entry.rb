module Bulkrax
  class OaiEntry < Entry
    def entry_class
      Work
    end

    def raw_record
      @raw_record ||= client.get_record({identifier: identifier, metadata_prefix: parser.parser_fields['metadata_prefix'] })
    end
  end
end
