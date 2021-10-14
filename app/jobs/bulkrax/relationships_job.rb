# frozen_string_literal: true

module Bulkrax
  class RelationshipsJob < ApplicationJob
    queue_as :import

    def entry
      @entry ||= Entry.find(@args[0])
    end

    def importer_run_id
      @args[2]
    end

    def user
      @user ||= entry.importerexporter.user
    end

    private

    # rubocop:disable Rails/SkipsModelValidations
    # Work-Collection membership is added to the child as member_of_collection_ids
    # This is adding the reverse relatinship, from the child to the parent
    def work_child_collection_parent(work_id)
      attrs = { id: work_id, collections: [{ id: entry&.factory&.find&.id }] }
      ObjectFactory.new(attributes: attrs,
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
      ObjectFactory.new(attributes: attrs,
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
      ObjectFactory.new(attributes: attrs,
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
  end
end
