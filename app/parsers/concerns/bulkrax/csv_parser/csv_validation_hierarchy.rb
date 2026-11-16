# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    # Hierarchy-building helpers for CsvValidation. Handles extracting and
    # categorising items from parsed CSV data for the guided import tree view.
    module CsvValidationHierarchy
      def extract_validation_items(csv_data, all_ids = Set.new, find_record = nil, parent_split_pattern: nil, child_split_pattern: nil, # rubocop:disable Metrics/ParameterLists
                                   parent_columns: ['parents'], children_columns: ['children'], find_existing_record: nil, deleted_ids: Set.new)
        child_to_parents = build_child_to_parents_map(csv_data, child_split_pattern: child_split_pattern, children_columns: children_columns)
        collections = []
        works       = []
        file_sets   = []
        taken_ids   = ids_in_csv(csv_data, parent_split_pattern: parent_split_pattern, child_split_pattern: child_split_pattern,
                                           parent_columns: parent_columns, children_columns: children_columns)

        csv_data.each_with_index do |item, index|
          categorise_validation_item(item, child_to_parents, all_ids, collections, works, file_sets, find_record,
                                     row_id: display_id(item, index + 2, taken_ids),
                                     parent_split_pattern: parent_split_pattern, child_split_pattern: child_split_pattern,
                                     parent_columns: parent_columns, children_columns: children_columns,
                                     find_existing_record: find_existing_record, deleted_ids: deleted_ids)
        end

        [collections, works, file_sets]
      end

      def build_child_to_parents_map(csv_data, child_split_pattern: nil, children_columns: ['children'])
        Hash.new { |h, k| h[k] = [] }.tap do |map|
          csv_data.each do |item|
            next if item[:source_identifier].blank? || item[:deleting]

            collect_relationship_ids(item[:children], item[:raw_row], children_columns, split_pattern: child_split_pattern).each do |child_id|
              map[child_id] << item[:source_identifier]
            end
          end
        end
      end

      def categorise_validation_item(item, child_to_parents, all_ids, collections, works, file_sets, find_record = nil, parent_split_pattern: nil, child_split_pattern: nil, # rubocop:disable Metrics/ParameterLists
                                     parent_columns: ['parents'], children_columns: ['children'], row_id: nil, find_existing_record: nil,
                                     deleted_ids: Set.new)
        item_id   = row_id || item[:source_identifier]
        model_str = item[:model].to_s

        opts = { type: nil, find_record: find_record, find_existing_record: find_existing_record, parent: parent_split_pattern,
                 child: child_split_pattern, parent_columns: parent_columns, children_columns: children_columns, id: item_id,
                 deleted_ids: deleted_ids }
        if Bulkrax.collection_model_name?(model_str)
          collections << build_item_hash(item, child_to_parents, all_ids, opts.merge(type: 'collection'))
        elsif Bulkrax.file_model_name?(model_str)
          file_sets << { id: item_id, title: item[:raw_row]['title'] || item_id, type: 'file_set', deleting: item[:deleting] || false }
        else
          works << build_item_hash(item, child_to_parents, all_ids, opts.merge(type: 'work'))
        end
      end

      def build_item_hash(item, child_to_parents, all_ids, opts = {}) # rubocop:disable Metrics/MethodLength
        type = opts[:type]
        find_record = opts[:find_record]
        item_id  = opts[:id] || item[:source_identifier]
        title    = item[:raw_row]['title'] || item_id
        # Import makes no relationship to or from a row it deletes
        # (ImportBehavior#parent_jobs), so the tree draws none.
        parents, children, named_by = if item[:deleting]
                                        [[], [], []]
                                      else
                                        [collect_relationship_ids(item[:parent], item[:raw_row], opts[:parent_columns] || ['parents'], split_pattern: opts[:parent]),
                                         collect_relationship_ids(item[:children], item[:raw_row], opts[:children_columns] || ['children'], split_pattern: opts[:child]),
                                         child_to_parents.fetch(item[:source_identifier], [])]
                                      end
        parents, children, named_by = [parents, children, named_by].map { |ids| ids.reject { |id| opts[:deleted_ids]&.include?(id) } }

        {
          id: item_id,
          title: title,
          type: type,
          existing: !item[:deleting] && existing_record?(item, opts[:find_existing_record]),
          deleting: item[:deleting] || false,
          parentIds: (resolvable_ids(parents, all_ids) + resolvable_ids(named_by, all_ids)).uniq,
          childIds: resolvable_ids(children, all_ids),
          existingParentIds: external_ids(parents, all_ids, find_record),
          existingChildIds: external_ids(children, all_ids, find_record)
        }
      end

      def existing_record?(item, find_existing_record)
        match = find_existing_record&.call(item)
        match.present? && !match[:missing] && !match[:existing_model] && !match[:lookup_failed]
      end

      # The tree needs a unique id for every row; blank ones arrive in the browser
      # as null and collide. The stand-in is for display only, never for lookups,
      # and skips any id the CSV already uses, or the row could become its own
      # parent in the tree.
      def display_id(item, row_number, taken_ids)
        return item[:source_identifier] if item[:source_identifier].present?

        stand_in = "row-#{row_number}"
        suffix = 0
        stand_in = "row-#{row_number}-#{suffix += 1}" while taken_ids.include?(stand_in)
        taken_ids << stand_in
        stand_in
      end

      def ids_in_csv(csv_data, parent_split_pattern:, child_split_pattern:, parent_columns:, children_columns:)
        csv_data.each_with_object(Set.new) do |item, ids|
          ids << item[:source_identifier] if item[:source_identifier].present?
          ids.merge(collect_relationship_ids(item[:parent], item[:raw_row], parent_columns, split_pattern: parent_split_pattern))
          ids.merge(collect_relationship_ids(item[:children], item[:raw_row], children_columns, split_pattern: child_split_pattern))
        end
      end

      def collect_relationship_ids(base_value, raw_row, columns, split_pattern: nil)
        Bulkrax::CsvRow::RelationshipIds.ids(base_value, raw_row, Array(columns), split_pattern)
      end

      def resolvable_ids(ids, all_ids)
        ids.select { |id| all_ids.include?(id) }
      end

      # Returns ids from the list that are NOT in the CSV but exist in the repository.
      def external_ids(ids, all_ids, find_record)
        return [] if find_record.nil?

        ids.reject { |id| all_ids.include?(id) }
           .select { |id| find_record.call(id) }
      end
    end
  end
end
