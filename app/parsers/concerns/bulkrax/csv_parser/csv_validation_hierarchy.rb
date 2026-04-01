# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    # Hierarchy-building helpers for CsvValidation. Handles extracting and
    # categorising items from parsed CSV data for the guided import tree view.
    module CsvValidationHierarchy
      def extract_validation_items(csv_data, all_ids = Set.new, find_record = nil, parent_split_pattern: nil, child_split_pattern: '|')
        child_to_parents = build_child_to_parents_map(csv_data, child_split_pattern: child_split_pattern)
        collections = []
        works       = []
        file_sets   = []

        csv_data.each do |item|
          categorise_validation_item(item, child_to_parents, all_ids, collections, works, file_sets, find_record,
                                     parent_split_pattern: parent_split_pattern, child_split_pattern: child_split_pattern)
        end

        [collections, works, file_sets]
      end

      def build_child_to_parents_map(csv_data, child_split_pattern: '|')
        Hash.new { |h, k| h[k] = [] }.tap do |map|
          csv_data.each do |item|
            next if item[:source_identifier].blank?

            collect_relationship_ids(item[:children], item[:raw_row], 'children', split_pattern: child_split_pattern).each do |child_id|
              map[child_id] << item[:source_identifier]
            end
          end
        end
      end

      def categorise_validation_item(item, child_to_parents, all_ids, collections, works, file_sets, find_record = nil, parent_split_pattern: nil, child_split_pattern: '|') # rubocop:disable Metrics/ParameterLists
        item_id   = item[:source_identifier]
        model_str = item[:model].to_s

        opts = { type: nil, find_record: find_record, parent: parent_split_pattern, child: child_split_pattern }
        if model_str.casecmp('collection').zero? || model_str.casecmp('collectionresource').zero?
          collections << build_item_hash(item, child_to_parents, all_ids, opts.merge(type: 'collection'))
        elsif model_str.casecmp('fileset').zero? || model_str.casecmp('hyrax::fileset').zero?
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
        parents  = collect_relationship_ids(item[:parent],   item[:raw_row], 'parents',  split_pattern: opts[:parent])
        children = collect_relationship_ids(item[:children], item[:raw_row], 'children', split_pattern: opts[:child] || '|')

        {
          id: item_id,
          title: title,
          type: type,
          parentIds: (resolvable_ids(parents, all_ids) + resolvable_ids(child_to_parents[item_id] || [], all_ids)).uniq,
          childIds: resolvable_ids(children, all_ids),
          existingParentIds: external_ids(parents, all_ids, find_record),
          existingChildIds: external_ids(children, all_ids, find_record)
        }
      end

      def parse_relationship_field(value, split_pattern: '|')
        return [] if value.blank?
        value.to_s.split(split_pattern).map(&:strip).reject(&:blank?)
      end

      def collect_relationship_ids(base_value, raw_row, column, split_pattern: '|')
        base_ids = parse_relationship_field(base_value, split_pattern: split_pattern)
        suffix_pattern = /\A#{Regexp.escape(column)}_\d+\z/
        suffix_ids = raw_row
                     .select { |k, _| k.to_s.match?(suffix_pattern) }
                     .values
                     .map(&:to_s).map(&:strip).reject(&:blank?)
        (base_ids + suffix_ids).uniq
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
