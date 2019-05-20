require 'language_list'
require 'erb'
require 'ostruct'

module Bulkrax
  class OaiEntry < Entry
    def entry_class
      Work
    end

    def raw_record
      @raw_record ||= client.get_record({identifier: identifier, metadata_prefix: parser.parser_fields['metadata_prefix'] })
    end

    def record
      raw_record.record
    end

    def rights_statement
      parser.parser_fields['rights_statement']
    end

    # try and deal with a couple possible states for this input field
    def override_rights_statement
      ['true', '1'].include?(parser.parser_fields['override_rights_statement'].to_s)
    end

    def contributing_institution
      parser.parser_fields['institution_name']
    end

    def context
      @context ||= OpenStruct.new(record: record, identifier: record.header.identifier)
    end

    def thumbnail_url
      ERB.new(parser.parser_fields['thumbnail_url']).result(context.instance_eval { binding })
    end

    def build_metadata
      self.parsed_metadata = {}

      record.metadata.children.each do |child|
        child.children.each do |node|
          add_metadata(node.name, node.content)
        end
      end
      add_metadata('thumbnail_url', thumbnail_url)

      self.parsed_metadata['contributing_institution'] = [contributing_institution]
      if override_rights_statement || self.parsed_metadata['rights_statement'].blank?
        self.parsed_metadata['rights_statement'] = [rights_statement]
      end
      self.parsed_metadata['visibility'] = 'open'
      self.parsed_metadata['source'] ||= [record.header.identifier]

      if collection.present?
        self.parsed_metadata['collections'] ||= []
        self.parsed_metadata['collections'] << {id: self.collection.id}
      end

      return self.parsed_metadata
    end

  end
end
