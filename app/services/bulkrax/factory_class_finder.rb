# frozen_string_literal: true

module Bulkrax
  class FactoryClassFinder
    ##
    # @param entry [Bulkrax::Entry]
    # @return [Class]
    def self.find(entry:)
      new(entry: entry).find
    end

    def initialize(entry:)
      @entry = entry
    end
    attr_reader :entry

    ##
    # @return [Class] when we are able to derive the class based on the {#name}.
    # @return [Nil] when we encounter errors with constantizing the {#name}.
    # @see #name
    def find
      # TODO: We have a string, now we want to consider how we coerce.  Let's say we have Work and
      # WorkResource in our upstream application.  Work extends ActiveFedora::Base and is legacy.
      # And WorkResource extends Valkyrie::Resource and is where we want to be moving.  We may want
      # to coerce the "Work" name into "WorkResource"
      name.constantize
    rescue NameError
      nil
    rescue
      entry.default_work_type.constantize
    end

    ##
    # @api private
    # @return [String]
    def name
      fc = if entry.parsed_metadata&.[]('model').present?
             Array.wrap(entry.parsed_metadata['model']).first
           elsif entry.importerexporter&.mapping&.[]('work_type').present?
             # Because of delegation's nil guard, we're reaching rather far into the implementation
             # details.
             Array.wrap(entry.parsed_metadata['work_type']).first
           else
             # The string might be frozen, so lets duplicate
             entry.default_work_type.dup
           end

      # Let's coerce this into the right shape.
      fc.tr!(' ', '_')
      fc.downcase! if fc.match?(/[-_]/)
      fc.camelcase
    rescue
      entry.default_work_type
    end
  end
end
