module Bulkrax
  class ApplicationParser

    attr_accessor :importer, :total
    delegate :only_updates, :limit, :current_importer_run, :increment_counters, :parser_fields, :user, to: :importer

    def self.parser_fields
      {}
    end

    def initialize(importer)
      @importer = importer
    end

    # @api
    def entry_class
      raise 'must be defined'
    end

    # @api
    def mapping_class
      raise 'must be defined'
    end

    # @api
    def records(opts = {})
      raise 'must be defined'
    end

    def record(identifier, opts = {})
      return @record if @record

      @record = entry_class.new(self, identifier)
      @record.build
      return @record
    end

    def total
      0
    end

  end
end
