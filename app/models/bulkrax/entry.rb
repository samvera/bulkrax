module Bulkrax
  class Entry < ApplicationRecord
    include Bulkrax::Concerns::HasMatchers
    belongs_to :importer
    serialize :parsed_metadata, JSON
    serialize :raw_metadata, JSON
    serialize :collection_ids, Array

    attr_accessor :all_attrs, :last_exception

    delegate :parser, :mapping,
             to: :importer

    delegate :client,
             :collection_name,
             :user,
             to: :parser

    # return true or false here
    def build
      # attributes, files_dir = nil, files = [], user = nil
      build_metadata
      return false unless collections_created?
      begin
        @item = Bulkrax::ApplicationFactory.for(factory_class.to_s).new(self.parsed_metadata, parser.files_path, [], user).run
      rescue StandardError => e
        status_info(e)
      else
        status_info
      end
      return @item
    end

    def find_or_create_collection_ids
      self.collection_ids
    end

    # override this to ensure any collections have been created before building the work
    def collections_created?
      true
    end

    def build_metadata
      raise 'Not Implemented'
    end

    def rights_statement
      parser.parser_fields['rights_statement']
    end

    # try and deal with a couple possible states for this input field
    def override_rights_statement
      %w[true 1].include?(parser.parser_fields['override_rights_statement'].to_s)
    end

    def blank_rights_statement
      %w[true 1].include?(parser.parser_fields['blank_rights_statement'].to_s)
    end

    def add_rights_statement
      if blank_rights_statement
        self.parsed_metadata['rights_statement'] = nil
      elsif override_rights_statement || self.parsed_metadata['rights_statement'].blank?
        self.parsed_metadata['rights_statement'] = [parser.parser_fields['rights_statement']] 
      end
    end

    def add_visibility
      self.parsed_metadata['visibility'] = 'open' if self.parsed_metadata['visibility'].blank?
    end

    def add_collections
      if find_or_create_collection_ids.present?
        self.parsed_metadata['collections'] ||= []
        self.parsed_metadata['collections'] += find_or_create_collection_ids.map { |c| { id: c } }
      end
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
