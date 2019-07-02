module Bulkrax
  class Entry < ApplicationRecord
    belongs_to :importer
    serialize :parsed_metadata, JSON

    attr_accessor :all_attrs, :last_exception

    delegate :parser,
             to: :importer

    delegate :client,
             :collection_name,
             :user,
             to: :parser

    def build
      # attributes, files_dir = nil, files = [], user = nil
      begin
        @item = Bulkrax::ApplicationFactory.for(factory_class.to_s).new(build_metadata, parser.files_path, [], user).run
      rescue => e
        status_info(e)
      else
        status_info
        self.collection_id = @item.id if @item.is_a?(Collection)
      end
      return @item
    end

    def collection
      @collection ||= Collection.find(self.collection_id) if self.collection_id
    end

    def build_metadata
      raise 'Not Implemented'
    end

    def add_visibility
      self.parsed_metadata['visibility'] = 'open' if self.parsed_metadata['visibility'].blank?
    end

    def add_rights_statement
      if override_rights_statement || self.parsed_metadata['rights_statement'].blank?
        self.parsed_metadata['rights_statement'] = [parser.parser_fields['rights_statement']]
      end
    end

    def override_rights_statement
      ['true', '1'].include?(parser.parser_fields['override_rights_statement'].to_s)
    end

    def factory_class
      Work
    end

    def status
      if self.last_error_at.present?
        'failed'
      elsif self.last_succeeded_at.present?
        'succeeded'
      else
        'waiting'
      end
    end

    def status_at
      case status
      when 'succeeded'
        self.last_succeeded_at
      when 'failed'
        self.last_error_at
      end
    end

    def status_info(e = nil)
      if e.nil?
        self.last_error = nil
        self.last_error_at = nil
        self.last_exception = nil
        self.last_succeeded_at = Time.now
      else
        self.last_error = "#{e.message}\n\n#{e.backtrace}"
        self.last_error_at = Time.now
        self.last_exception = e
      end
    end
  end
end
