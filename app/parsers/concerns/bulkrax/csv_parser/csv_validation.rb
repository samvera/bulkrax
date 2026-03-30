# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    module CsvValidation # rubocop:disable Metrics/ModuleLength
      extend ActiveSupport::Concern

      included do
        # Lightweight struct used to satisfy the CsvTemplate::ColumnBuilder
        # interface without constructing a full template context.
        ValidationContext = Struct.new(:mapping_manager, :field_analyzer, :all_models, :mappings, keyword_init: true)
      end

      class_methods do
        # Validate a CSV (and optional zip) without a persisted Importer record.
        #
        # @param csv_file [File, ActionDispatch::Http::UploadedFile, String] path or file object
        # @param zip_file [File, ActionDispatch::Http::UploadedFile, nil]
        # @param admin_set_id [String, nil]
        # @return [Hash] validation result compatible with the guided import UI
        def validate_csv(csv_file:, zip_file: nil, admin_set_id: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          # 1. Read headers — use CsvEntry.read_data so header normalisation
          #    (special-char stripping, symbolisation) is identical to a real import.
          raw_csv = CsvEntry.read_data(csv_file)
          headers = raw_csv.headers.map(&:to_s)

          # 2. Field mappings / column name resolution
          mapping_manager = CsvTemplate::MappingManager.new
          mappings        = mapping_manager.mappings

          source_id_key  = resolve_validation_key(mapping_manager, flag: 'source_identifier',                    default: :source_identifier)
          parent_key     = resolve_validation_key(mapping_manager, flag: 'related_parents_field_mapping',        default: :parents)
          children_key   = resolve_validation_key(mapping_manager, flag: 'related_children_field_mapping',       default: :children)
          file_key       = resolve_validation_key(mapping_manager, key: 'file',                                  default: :file)

          # 3. Parse rows — CsvEntry.read_data already filters blank rows and
          #    returns symbol-keyed rows (same as a real import).
          csv_data = parse_validation_rows(raw_csv, source_id_key, parent_key, children_key, file_key)

          # 4. Field metadata
          all_models     = csv_data.map { |r| r[:model] }.compact.uniq
          field_analyzer = CsvTemplate::FieldAnalyzer.new(mappings, admin_set_id)
          field_metadata = build_validation_field_metadata(all_models, field_analyzer)

          # 5. Valid-header set (drives unrecognised-header detection)
          valid_headers = build_valid_validation_headers(mapping_manager, field_analyzer, all_models, mappings, field_metadata)

          # 6. Suffixed variants seen in this specific CSV (e.g. title_1, creator_2)
          suffixed_headers = headers.select { |h| h.match?(/_\d+\z/) }
          valid_headers = (valid_headers + suffixed_headers).uniq

          # 7. Header-level checks
          missing_required = find_missing_required_headers(headers, field_metadata, mapping_manager)
          unrecognized     = find_unrecognized_validation_headers(headers, valid_headers)
          empty_columns    = find_empty_column_positions(headers, raw_csv)

          # 8. Row-level validators
          parent_split      = resolve_parent_split_pattern(mappings)
          all_ids           = csv_data.map { |r| r[:source_identifier] }.compact.to_set
          validator_context = {
            errors: [],
            warnings: [],
            seen_ids: {},
            all_ids: all_ids,
            source_identifier: source_id_key.to_s,
            parent_split_pattern: parent_split,
            mappings: mappings,
            field_metadata: field_metadata
          }

          csv_data.each_with_index do |record, index|
            row_number = index + 2 # 1-indexed, plus header row
            Bulkrax.csv_row_validators.each { |v| v.call(record, row_number, validator_context) }
          end

          # 9. File validation
          file_validator = CsvTemplate::FileValidator.new(csv_data, zip_file, admin_set_id)

          # 10. Item hierarchy for UI display
          collections, works, file_sets = extract_validation_items(csv_data)

          # 11. Assemble result
          row_errors  = validator_context[:errors]
          has_errors  = missing_required.any? || headers.blank? || csv_data.empty? ||
                        file_validator.missing_files.any? || row_errors.any?
          has_warnings = unrecognized.any? || empty_columns.any? || file_validator.possible_missing_files?

          result = {
            headers: headers,
            missingRequired: missing_required,
            unrecognized: unrecognized,
            emptyColumns: empty_columns,
            rowCount: csv_data.length,
            isValid: !has_errors,
            hasWarnings: has_warnings,
            rowErrors: row_errors,
            collections: collections,
            works: works,
            fileSets: file_sets,
            totalItems: csv_data.length,
            fileReferences: file_validator.count_references,
            missingFiles: file_validator.missing_files,
            foundFiles: file_validator.found_files_count,
            zipIncluded: file_validator.zip_included?
          }

          apply_rights_statement_validation_override!(result, missing_required)
          result
        end

        private

        # Resolve a symbol key from mappings for use as a record hash key.
        # Returns a Symbol matching the parser's symbol-keyed record hash.
        def resolve_validation_key(mapping_manager, key: nil, flag: nil, default:)
          options = mapping_manager.resolve_column_name(key: key, flag: flag, default: default.to_s)
          options.first&.to_sym || default
        end

        # Parse rows from a CsvEntry.read_data result into the canonical record shape.
        # CsvEntry.read_data returns CSV::Row objects with symbol headers; blank rows
        # are already filtered by CsvWrapper.
        def parse_validation_rows(raw_csv, source_id_key, parent_key, children_key, file_key)
          raw_csv.map do |row|
            # CSV::Row#to_h converts symbol headers → string-keyed hash
            row_hash = row.to_h.transform_keys(&:to_s)
            {
              source_identifier: row[source_id_key],
              model: row[:model],
              parent: row[parent_key],
              children: row[children_key],
              file: row[file_key],
              raw_row: row_hash
            }
          end
        rescue StandardError => e
          Rails.logger.error("CsvParser.validate_csv: error parsing rows – #{e.message}")
          []
        end

        def build_validation_field_metadata(all_models, field_analyzer)
          all_models.each_with_object({}) do |model, hash|
            field_list = field_analyzer.find_or_create_field_list_for(model_name: model)
            hash[model] = {
              properties: field_list.dig(model, 'properties') || [],
              required_terms: field_list.dig(model, 'required_terms') || [],
              controlled_vocab_terms: field_list.dig(model, 'controlled_vocab_terms') || []
            }
          end
        end

        def build_valid_validation_headers(mapping_manager, field_analyzer, all_models, mappings, field_metadata)
          svc = ValidationContext.new(
            mapping_manager: mapping_manager,
            field_analyzer: field_analyzer,
            all_models: all_models,
            mappings: mappings
          )
          all_cols = CsvTemplate::ColumnBuilder.new(svc).all_columns
          all_cols - CsvTemplate::CsvBuilder::IGNORED_PROPERTIES
        rescue StandardError => e
          Rails.logger.error("CsvParser.validate_csv: error building valid headers – #{e.message}")
          standard = %w[model source_identifier parent parents file]
          model_fields = field_metadata.values.flat_map { |m| m[:properties] }
          (standard + model_fields).uniq
        end

        def find_missing_required_headers(headers, field_metadata, mapping_manager)
          csv_keys = headers.map { |h| mapping_manager.mapped_to_key(h).sub(/_\d+\z/, '') }.uniq
          missing = []
          field_metadata.each do |model, meta|
            (meta[:required_terms] || []).each do |field|
              missing << { model: model, field: field } unless csv_keys.include?(field)
            end
          end
          missing.uniq
        end

        def find_unrecognized_validation_headers(headers, valid_headers)
          checker = DidYouMean::SpellChecker.new(dictionary: valid_headers)
          headers
            .reject { |h| h.blank? || valid_headers.include?(h) || valid_headers.include?(h.sub(/_\d+\z/, '')) }
            .index_with { |h| checker.correct(h).first }
        end

        def find_empty_column_positions(headers, raw_csv)
          headers.each_with_index.filter_map do |h, i|
            next if h.present?
            has_data = raw_csv.any? { |row| row.fields[i].present? }
            i + 1 if has_data
          end
        end

        def resolve_parent_split_pattern(mappings)
          split_val = mappings.dig('parents', 'split') || mappings.dig(:parents, :split)
          return nil if split_val.blank?
          return Bulkrax::DEFAULT_MULTI_VALUE_ELEMENT_SPLIT_ON if split_val == true

          split_val
        end

        def extract_validation_items(csv_data) # rubocop:disable Metrics/MethodLength
          child_to_parents = build_child_to_parents_map(csv_data)
          collections = []
          works       = []
          file_sets   = []

          csv_data.each do |item|
            categorise_validation_item(item, child_to_parents, collections, works, file_sets)
          end

          [collections, works, file_sets]
        end

        def build_child_to_parents_map(csv_data)
          Hash.new { |h, k| h[k] = [] }.tap do |map|
            csv_data.each do |item|
              parse_relationship_field(item[:children]).each do |child_id|
                map[child_id] << item[:source_identifier]
              end
            end
          end
        end

        def categorise_validation_item(item, child_to_parents, collections, works, file_sets)
          item_id   = item[:source_identifier]
          title     = item[:raw_row]['title'] || item_id
          model_str = item[:model].to_s

          if model_str.casecmp('collection').zero? || model_str.casecmp('collectionresource').zero?
            explicit = parse_relationship_field(item[:parent])
            inferred = child_to_parents[item_id] || []
            collections << { id: item_id, title: title, type: 'collection',
                             parentIds: (explicit + inferred).uniq,
                             childIds: parse_relationship_field(item[:children]) }
          elsif model_str.casecmp('fileset').zero? || model_str.casecmp('hyrax::fileset').zero?
            file_sets << { id: item_id, title: title, type: 'file_set' }
          else
            explicit = parse_relationship_field(item[:parent])
            inferred = child_to_parents[item_id] || []
            works << { id: item_id, title: title, type: 'work',
                       parentIds: (explicit + inferred).uniq,
                       childIds: parse_relationship_field(item[:children]) }
          end
        end

        def parse_relationship_field(value)
          return [] if value.blank?
          value.to_s.split('|').map(&:strip).reject(&:blank?)
        end

        def apply_rights_statement_validation_override!(result, missing_required)
          only_rights = missing_required.present? &&
                        missing_required.all? { |h| h[:field].to_s == 'rights_statement' }
          return unless only_rights && !result[:isValid]
          return if result[:headers].blank?
          return if result[:missingFiles]&.any?

          result[:isValid]     = true
          result[:hasWarnings] = true
        end
      end
    end
  end
end
