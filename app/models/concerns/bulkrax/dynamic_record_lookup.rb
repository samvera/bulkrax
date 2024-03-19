# frozen_string_literal: true

module Bulkrax
  # TODO: Extract methods to class methods; there's no reason for these methods to be a mixin.
  # TODO: Add specs to test in isolation
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
      default_scope = { identifier: identifier, importerexporter_type: 'Bulkrax::Importer' }

      begin
        # the identifier parameter can be a :source_identifier or the id of an object
        record = Entry.find_by(default_scope.merge({ importerexporter_id: importer_id })) || Entry.find_by(default_scope)
        record ||= ActiveFedora::Base.find(identifier)
      # NameError for if ActiveFedora isn't installed
      rescue NameError, ActiveFedora::ObjectNotFoundError
        record = nil
      end

      # return the found entry here instead of searching for it again in the CreateRelationshipsJob
      # also accounts for when the found entry isn't a part of this importer
      record.is_a?(Entry) ? [record, record.factory.find] : [nil, record]
    end
  end
end
