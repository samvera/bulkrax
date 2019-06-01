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
        Bulkrax::ApplicationFactory.for(entry_class.to_s).new(build_metadata, nil, [], user).run
      rescue => e
        self.last_error = "#{e.message}\n\n#{e.backtrace}"
        self.last_error_at = Time.now
        self.last_exception = e
      else
        self.last_error = nil
        self.last_error_at = nil
        self.last_exception = nil
        self.last_succeeded_at = Time.now
      end
    end

    def collection
      @collection ||= Collection.find(self.collection_id) if self.collection_id
    end

    def build_metadata
      raise 'Not Implemented'
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
  end
end
