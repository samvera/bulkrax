# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    module CsvValidation
      extend ActiveSupport::Concern

      included do
        # Lightweight struct used to satisfy the CsvTemplate::ColumnBuilder
        # interface without constructing a full template context.
        ValidationContext = Struct.new(:mapping_manager, :field_analyzer, :all_models, :mappings, keyword_init: true)
      end

      class_methods do
        include CsvValidationHelpers

        # Validate a CSV (and optional zip) without a persisted Importer record.
        #
        # @param csv_file [File, ActionDispatch::Http::UploadedFile, String] path or file object
        # @param zip_file [File, ActionDispatch::Http::UploadedFile, nil]
        # @param admin_set_id [String, nil]
        # @return [Hash] validation result compatible with the guided import UI
        def validate_csv(csv_file:, zip_file: nil, admin_set_id: nil)
          raw_csv, headers, mapping_manager, mappings, source_id_key, csv_data, field_metadata, field_analyzer =
            parse_csv_inputs(csv_file, admin_set_id)

          all_ids = csv_data.map { |r| r[:source_identifier] }.compact.to_set

          header_issues    = check_headers(headers, raw_csv, mapping_manager, mappings, field_metadata, field_analyzer)
          missing_required = header_issues[:missing_required]
          find_record      = build_find_record(mapping_manager, mappings)
          row_errors       = run_row_validators(csv_data, all_ids, source_id_key, mappings, field_metadata, find_record)
          file_validator   = CsvTemplate::FileValidator.new(csv_data, zip_file, admin_set_id)
          collections, works, file_sets = extract_hierarchy_items(csv_data, all_ids, find_record, mappings)

          append_missing_source_id!(missing_required, headers, source_id_key, csv_data.map { |r| r[:model] }.compact.uniq)

          result = assemble_result(
            headers: headers,
            missing_required: missing_required,
            header_issues: header_issues,
            row_errors: row_errors,
            csv_data: csv_data,
            file_validator: file_validator,
            collections: collections,
            works: works,
            file_sets: file_sets
          )
          apply_rights_statement_validation_override!(result, missing_required)
          result
        end

        private

        # Reads the CSV, resolves mappings, parses rows, and builds field metadata.
        # Returns the values needed by all subsequent validation steps.
        def parse_csv_inputs(csv_file, admin_set_id)
          # Use CsvEntry.read_data so header normalisation is identical to a real import.
          raw_csv = CsvEntry.read_data(csv_file)
          headers = raw_csv.headers.map(&:to_s)

          mapping_manager = CsvTemplate::MappingManager.new
          mappings        = mapping_manager.mappings

          source_id_key = resolve_validation_key(mapping_manager, flag: 'source_identifier', default: :source_identifier)
          parent_key    = resolve_validation_key(mapping_manager, flag: 'related_parents_field_mapping',  default: :parents)
          children_key  = resolve_validation_key(mapping_manager, flag: 'related_children_field_mapping', default: :children)
          file_key      = resolve_validation_key(mapping_manager, key: 'file',                            default: :file)

          csv_data       = parse_validation_rows(raw_csv, source_id_key, parent_key, children_key, file_key)
          all_models     = csv_data.map { |r| r[:model] }.compact.uniq
          field_analyzer = CsvTemplate::FieldAnalyzer.new(mappings, admin_set_id)
          field_metadata = build_validation_field_metadata(all_models, field_analyzer)

          [raw_csv, headers, mapping_manager, mappings, source_id_key, csv_data, field_metadata, field_analyzer]
        end

        # Runs all header-level checks and returns a hash of results.
        def check_headers(headers, raw_csv, mapping_manager, mappings, field_metadata, field_analyzer) # rubocop:disable Metrics/ParameterLists
          all_models    = field_metadata.keys
          valid_headers = build_valid_validation_headers(mapping_manager, field_analyzer,
                                                         all_models, mappings, field_metadata)
          suffixed      = headers.select { |h| h.match?(/_\d+\z/) }
          valid_headers = (valid_headers + suffixed).uniq

          {
            missing_required: find_missing_required_headers(headers, field_metadata, mapping_manager),
            unrecognized: find_unrecognized_validation_headers(headers, valid_headers),
            empty_columns: find_empty_column_positions(headers, raw_csv)
          }
        end

        def extract_hierarchy_items(csv_data, all_ids, find_record, mappings)
          extract_validation_items(
            csv_data, all_ids, find_record,
            parent_split_pattern: resolve_parent_split_pattern(mappings),
            child_split_pattern: resolve_children_split_pattern(mappings) || '|'
          )
        end

        # Runs all registered row validators and returns the collected errors.
        def run_row_validators(csv_data, all_ids, source_id_key, mappings, field_metadata, find_record) # rubocop:disable Metrics/ParameterLists
          context = {
            errors: [],
            warnings: [],
            seen_ids: {},
            all_ids: all_ids,
            source_identifier: source_id_key.to_s,
            parent_split_pattern: resolve_parent_split_pattern(mappings),
            child_split_pattern: resolve_children_split_pattern(mappings),
            parent_column: resolve_relationship_column(mappings, 'related_parents_field_mapping', 'parents'),
            children_column: resolve_relationship_column(mappings, 'related_children_field_mapping', 'children'),
            mappings: mappings,
            field_metadata: field_metadata,
            find_record_by_source_identifier: find_record
          }
          csv_data.each_with_index do |record, index|
            row_number = index + 2 # 1-indexed, plus header row
            Bulkrax.csv_row_validators.each { |v| v.call(record, row_number, context) }
          end
          context[:errors]
        end
      end
    end
  end
end
