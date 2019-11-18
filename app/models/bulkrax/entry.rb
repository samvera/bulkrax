module Bulkrax
  class Entry < ApplicationRecord
    include Bulkrax::HasMatchers
    include Bulkrax::HasLocalProcessing
    include Bulkrax::ImportBehavior
    include Bulkrax::ExportBehavior

    belongs_to :importerexporter, polymorphic: true
    serialize :parsed_metadata, JSON
    # Do not serialize raw_metadata as so we can support xml or other formats
    serialize :collection_ids, Array

    attr_accessor :all_attrs, :last_exception

    delegate :parser, :mapping, to: :importerexporter

    delegate :client,
             :collection_name,
             :user,
             to: :parser

    def build
      return false if type.nil?
      build_for_importer if importer?
      build_for_exporter if exporter?
    end

    def importer?
      self.importerexporter_type == 'Bulkrax::Importer'
    end

    def exporter?
      self.importerexporter_type == 'Bulkrax::Exporter'
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
    
    def valid_system_id(model_class)
      raise(
        "#{model_class} does not implement the system_identifier_field: #{Bulkrax.system_identifier_field}"
      ) unless model_class.properties.keys.include?(Bulkrax.system_identifier_field)
    end

    def find_collection(collection_identifier)
      Collection.where(
        Bulkrax.system_identifier_field => collection_identifier
      ).detect { |m| m.send(Bulkrax.system_identifier_field).include?(collection_identifier) }
    end
  end
end
