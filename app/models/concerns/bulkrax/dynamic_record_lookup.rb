# frozen_string_literal: true

module Bulkrax
  module DynamicRecordLookup
    # Search entries, collections, and every available work type for a record that
    # has the provided identifier.
    #
    # @param identifier [String] Work/Collection ID or Bulkrax::Entry source_identifier
    # @param importer_run_id [Number] ID of the current_run of this Importer Job
    # @return [Entry, nil], [Work, Collection, nil] Entry if found, otherwise nil and a Work or Collection if found, otherwise nil
    def find_record(identifier, importer_run_id = nil)
      # check for our entry in our current importer first
      importer_id = ImporterRun.find(importer_run_id).importer_id
      record = Entry.find_by(identifier: identifier, importerexporter_id: importer_id) || Entry.find_by(identifier: identifier)

      # TODO(alishaevn): discuss whether we are only looking for Collection models here
      # use ActiveFedora::Base.find(identifier) instead?
      record ||= ::Collection.where(id: identifier).first # rubocop:disable Rails/FindBy
      if record.blank?
        available_work_types.each do |work_type|
          record ||= work_type.where(id: identifier).first # rubocop:disable Rails/FindBy
        end
      end

      # return the found entry here instead of searching for it again in the CreateRelationshipsJob
      # also accounts for when the found entry isn't a part of this importer
      record.is_a?(Entry) ? [record, record.factory.find] : [nil, record]
    end

    # Check if the record is a Work
    def curation_concern?(record)
      available_work_types.include?(record.class)
    end

    private

    # @return [Array<Class>] list of work type classes
    def available_work_types
      # If running in a Hyku app, do not include disabled work types
      @available_work_types ||= if defined?(::Hyku)
                                  ::Site.instance.available_works.map(&:constantize)
                                else
                                  ::Hyrax.config.curation_concerns
                                end
    end
  end
end
