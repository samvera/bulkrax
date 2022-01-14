# frozen_string_literal: true

module Bulkrax
  module DynamicRecordLookup
    # Search entries, collections, and every available work type for a record that
    # has the provided identifier.
    #
    # @param identifier [String] Work/Collection ID or Bulkrax::Entry source_identifier
    # @return [Work, Collection, nil] Work or Collection if found, otherwise nil
    def find_record(identifier)
      record = Entry.find_by(identifier: identifier)
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
