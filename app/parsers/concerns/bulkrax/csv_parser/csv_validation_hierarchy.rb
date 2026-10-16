# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    # Hierarchy-building helpers for CsvValidation. Handles extracting and
    # categorising items from parsed CSV data for the guided import tree view.
    module CsvValidationHierarchy
      def extract_validation_items(csv_data, all_ids = Set.new, find_record = nil, parent_split_pattern: nil, child_split_pattern: nil, # rubocop:disable Metrics/ParameterLists
                                   parent_columns: ['parents'], children_columns: ['children'])
        child_to_parents = build_child_to_parents_map(csv_data, child_split_pattern: child_split_pattern, children_columns: children_columns)
        collections = []
        works       = []
        file_sets   = []

        csv_data.each do |item|
          categorise_validation_item(item, child_to_parents, all_ids, collections, works, file_sets, find_record,
                                     parent_split_pattern: parent_split_pattern, child_split_pattern: child_split_pattern,
                                     parent_columns: parent_columns, children_columns: children_columns)
        end

        [collections, works, file_sets]
      end

      def build_child_to_parents_map(csv_data, child_split_pattern: nil, children_columns: ['children'])
        Hash.new { |h, k| h[k] = [] }.tap do |map|
          csv_data.each do |item|
            next if item[:source_identifier].blank?

            collect_relationship_ids(item[:children], item[:raw_row], children_columns, split_pattern: child_split_pattern).each do |child_id|
              map[child_id] << item[:source_identifier]
            end
          end
        end
      end

      def categorise_validation_item(item, child_to_parents, all_ids, collections, works, file_sets, find_record = nil, parent_split_pattern: nil, child_split_pattern: nil, # rubocop:disable Metrics/ParameterLists
                                     parent_columns: ['parents'], children_columns: ['children'])
        item_id   = item[:source_identifier]
        model_str = item[:model].to_s

        opts = { type: nil, find_record: find_record, parent: parent_split_pattern, child: child_split_pattern,
                 parent_columns: parent_columns, children_columns: children_columns }
        if Bulkrax.collection_model_name?(model_str)
          collections << build_item_hash(item, child_to_parents, all_ids, opts.merge(type: 'collection'))
        elsif Bulkrax.file_model_name?(model_str)
          file_sets << { id: item_id, title: item[:raw_row]['title'] || item_id, type: 'file_set' }
        else
          works << build_item_hash(item, child_to_parents, all_ids, opts.merge(type: 'work'))
        end
      end

      def build_item_hash(item, child_to_parents, all_ids, opts = {}) # rubocop:disable Metrics/MethodLength
        type = opts[:type]
        find_record = opts[:find_record]
        item_id  = item[:source_identifier]
        title    = item[:raw_row]['title'] || item_id
        parents  = collect_relationship_ids(item[:parent],   item[:raw_row], opts[:parent_columns] || ['parents'], split_pattern: opts[:parent])
        children = collect_relationship_ids(item[:children], item[:raw_row], opts[:children_columns] || ['children'], split_pattern: opts[:child])

        {
          id: item_id,
          title: title,
          type: type,
          existing: find_record&.call(item_id) || false,
          parentIds: (resolvable_ids(parents, all_ids) + resolvable_ids(child_to_parents[item_id] || [], all_ids)).uniq,
          childIds: resolvable_ids(children, all_ids),
          existingParentIds: external_ids(parents, all_ids, find_record),
          existingChildIds: external_ids(children, all_ids, find_record)
        }
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
