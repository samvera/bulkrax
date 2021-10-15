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
    def collection_parent_work_child(parent_id:, child_id:)
      attrs = { id: child_id, collections: [{ id: parent_id }] }
      ObjectFactory.new(attributes: attrs,
                        source_identifier_value: child_works_hash[child_id][entry.parser.source_identifier],
                        work_identifier: entry.parser.work_identifier,
                        collection_field_mapping: entry.parser.collection_field_mapping,
                        replace_files: false,
                        user: user,
                        klass: child_works_hash[child_id][:class_name].constantize).run
      ImporterRun.find(importer_run_id).increment!(:processed_children)
    rescue StandardError => e
      entry.status_info(e)
      ImporterRun.find(importer_run_id).increment!(:failed_children)
    end

    # Collection-Collection membership is added to the as child_ids
    def collection_parent_collection_child(parent_id:, child_ids:)
      attrs = { id: parent_id, children: child_ids }
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

    # Work-Work membership is added to the parent as child_ids
    def work_parent_work_child(parent_id:, child_ids:)
      # build work_members_attributes
      attrs = { id: parent_id,
                work_members_attributes: child_ids.each.with_index.each_with_object({}) do |(member, index), ids|
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
