# frozen_string_literal: true

module Bulkrax
  class AttachItemsJob < ApplicationJob
    queue_as :import

    attr_accessor :child_record, :parent_record, :importer_run
    def perform(child_entry_id:, parent_entry_id: nil, parent_record_id: nil, importer_run: )
      # check if both entries exist, otherwise reschedule
      # figure out what kind of child we have and what kind of parent
      # attach them
      child_record = Bulkrax::Entry.find_by(identifier: child_entry_id)&.factory&.find
      # TODO make parent optional, make allow parent_id in stead
      parent_record = Bulkrax::Entry.find_by(identifier: parent_entry_id)&.factory&.find

      if child_record.blank? || parent_record.blank?
        reschedule(child_entry_id: child_entry_id, parent_entry_id: parent_entry_id, parent_record_id: parent_record_id)
        return
      end

      if parent_record.is_a?(Collection) && child_record.is_a?(Collection)
      elsif parent_record.is_a?(Collection)
        collection_membership
      else
        work_membership
      end
      # Not all of the Works/Collections exist yet; reschedule
    rescue ActiveRecord::RecordNotFound
    end

    def user
      @user ||= entry.importerexporter.user
    end

    private

    # rubocop:disable Rails/SkipsModelValidations
    # Work-Collection membership is added to the child as member_of_collection_ids
    # This is adding the reverse relatinship, from the child to the parent
    def work_child_collection_parent(work_id)
      attrs = { :id =>  work_id, entry.parser.collection_field_mapping => [{ id: entry&.factory&.find&.id }] }
      Bulkrax::ObjectFactory.new(attributes: attrs,
                                 source_identifier_value: child_works_hash[work_id][entry.parser.source_identifier],
                                 work_identifier: entry.parser.work_identifier,
                                 collection_field_mapping: entry.parser.collection_field_mapping,
                                 replace_files: false,
                                 user: user,
                                 klass: child_works_hash[work_id][:class_name].constantize).run
      ImporterRun.find(importer_run_id).increment!(:processed_children)
    rescue StandardError => e
      entry.status_info(e)
      ImporterRun.find(importer_run_id).increment!(:failed_children)
    end

    # Collection-Collection membership is added to the as member_ids
    def collection_parent_collection_child(member_ids)
      attrs = { id: entry&.factory&.find&.id, children: member_ids }
      Bulkrax::ObjectFactory.new(attributes: attrs,
                                 source_identifier_value: entry.identifier,
                                 work_identifier: entry.parser.work_identifier,
                                 collection_field_mapping: entry.parser.collection_field_mapping,
                                 replace_files: false,
                                 user: user,
                                 klass: entry.factory_class).run
      ImporterRun.find(importer_run_id).increment!(:processed_children)
    rescue StandardError => e
      entry.status_info(e)
      ImporterRun.find(importer_run_id).increment!(:failed_children)
    end

    # Work-Work membership is added to the parent as member_ids
    def work_parent_work_child(member_ids)
      # build work_members_attributes
      attrs = { id: entry&.factory&.find&.id,
                work_members_attributes: member_ids.each.with_index.each_with_object({}) do |(member, index), ids|
                  ids[index] = { id: member }
                end }
      Bulkrax::ObjectFactory.new(attributes: attrs,
                                 source_identifier_value: entry.identifier,
                                 work_identifier: entry.parser.work_identifier,
                                 collection_field_mapping: entry.parser.collection_field_mapping,
                                 replace_files: false,
                                 user: user,
                                 klass: entry.factory_class).run
      ImporterRun.find(importer_run_id).increment!(:processed_children)
    rescue StandardError => e
      entry.status_info(e)
      ImporterRun.find(importer_run_id).increment!(:failed_children)
    end
    # rubocop:enable Rails/SkipsModelValidations

    def reschedule(entry_id, child_entry_ids, importer_run_id)
      ChildRelationshipsJob.set(wait: 10.minutes).perform_later(entry_id, child_entry_ids, importer_run_id)
    end
  end
end
