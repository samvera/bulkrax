# frozen_string_literal: true

module Bulkrax
  module DynamicRecordLookup
    # Search entries, collections, and every available work type for a record that
    # has the provided identifier.
    #
    # @param identifier [String] Work/Collection ID or Bulkrax::Entry source_identifier
    # @param importer_run_id [Number] ID of the current_run of this Importer Job
    # @return [Work, Collection, nil] Work or Collection if found, otherwise nil
    def find_record(identifier, importer_run_id = nil)
      if importer_run_id
        # account for the possibility that the same record may have successfully or unsuccessfully
        # been imported in a different importer
        importer_id = ImporterRun.find(importer_run_id).importer_id
        record = Entry.find_by(identifier: identifier, importerexporter_id: importer_id)
      else
        # TODO(alishaevn): figure out how to access the importer_run_id in the "create_file_set" method
        # so this else can be removed
        record = Entry.find_by(identifier: identifier)
      end
      record ||= ::Collection.where(id: identifier).first # rubocop:disable Rails/FindBy
      if record.blank?
        available_work_types.each do |work_type|
          record ||= work_type.where(id: identifier).first # rubocop:disable Rails/FindBy
        end
      end

      record.is_a?(Entry) ? record.factory.find : record
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
