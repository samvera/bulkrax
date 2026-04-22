# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    # Private helper methods for CsvValidation.
    module CsvValidationHelpers # rubocop:disable Metrics/ModuleLength
      include CsvValidationHierarchy

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
        svc = Bulkrax::CsvParser::ValidationContext.new(
          mapping_manager: mapping_manager,
          field_analyzer: field_analyzer,
          all_models: all_models,
          mappings: mappings
        )
        all_cols = CsvTemplate::ColumnBuilder.new(svc).all_columns
        all_cols - CsvTemplate::CsvBuilder::IGNORED_PROPERTIES
      rescue StandardError => e
        Rails.logger.error("CsvParser.validate_csv: error building valid headers – #{e.message}")
        standard = %w[model source_identifier parents children file]
        model_fields = field_metadata.values.flat_map { |m| m[:properties] }
                                            .map { |prop| mapping_manager.key_to_mapped_column(prop) }
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

      # A header is considered recognised if it appears in valid_headers or
      # if it matches any alias in a known property's `from` array. The real
      # importer (CsvParser#missing_elements) scans every `from` entry when
      # matching incoming columns, so the validator has to use the same rule
      # — otherwise a CSV that imports cleanly gets flagged for columns like
      # `creator` when the mapping declares `creator: { from: ['author', 'creator'] }`.
      def find_unrecognized_validation_headers(headers, valid_headers, mapping_manager: nil, field_metadata: nil)
        known_property_keys = (field_metadata || {}).values.flat_map { |m| Array(m[:properties]) }.to_set
        checker = DidYouMean::SpellChecker.new(dictionary: valid_headers)
        unrecognized = headers.reject do |h|
          next true if h.blank?
          base = h.sub(/_\d+\z/, '')
          next true if valid_headers.include?(h) || valid_headers.include?(base)
          mapped_key = mapping_manager&.mapped_to_key(base)
          mapped_key && known_property_keys.include?(mapped_key)
        end
        unrecognized.index_with { |h| checker.correct(h).first }
      end

      def find_empty_column_positions(headers, raw_csv)
        headers.each_with_index.filter_map do |h, i|
          next if h.present?
          has_data = raw_csv.any? { |row| row.fields[i].present? }
          i + 1 if has_data
        end
      end

      # Adds a missing source_identifier entry to missing_required when the column
      # is absent and fill_in_blank_source_identifiers is not configured.
      def append_missing_source_id!(missing_required, headers, source_id_key, all_models)
        return if headers.map(&:to_s).include?(source_id_key.to_s)
        return if Bulkrax.fill_in_blank_source_identifiers.present?

        all_models.each { |model| missing_required << { model: model, field: source_id_key.to_s } }
      end

      # Adds a file-level notice when the model column is absent or every row has a blank
      # model value, indicating that the default work type will be used for all rows.
      # When this notice is present the per-row default_work_type_used warnings are
      # suppressed in the formatter — no need to repeat the same message for every row.
      def append_missing_model_notice!(notices, headers, csv_data)
        default_model = Bulkrax.default_work_type
        return if default_model.blank?

        model_column_present = headers.map(&:to_s).include?('model')
        all_rows_blank = model_column_present && csv_data.all? { |r| r[:model].blank? }

        return if model_column_present && !all_rows_blank

        key_suffix = all_rows_blank ? 'column_empty' : 'column_missing'
        base_key   = 'bulkrax.importer.guided_import.validation.default_work_type_notice'
        notices << {
          field: 'model',
          default_work_type: default_model,
          message: I18n.t("#{base_key}.message_#{key_suffix}", default_work_type: default_model),
          suggestion: I18n.t("#{base_key}.suggestion_#{key_suffix}")
        }
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

      # Assembles the final result hash returned to the guided import UI.
      def assemble_result(headers:, missing_required:, header_issues:, row_errors:, csv_data:, file_validator:, collections:, works:, file_sets:, notices: []) # rubocop:disable Metrics/ParameterLists
        row_error_entries   = row_errors.select { |e| e[:severity] == 'error' }
        row_warning_entries = row_errors.select { |e| e[:severity] == 'warning' }
        has_errors   = missing_required.any? || headers.blank? || csv_data.empty? ||
                       file_validator.missing_files.any? || row_error_entries.any?
        has_warnings = header_issues[:unrecognized].any? || header_issues[:empty_columns].any? ||
                       file_validator.possible_missing_files? || row_warning_entries.any? || notices.any?

        {
          headers: headers,
          missingRequired: missing_required,
          notices: notices,
          unrecognized: header_issues[:unrecognized],
          emptyColumns: header_issues[:empty_columns],
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
      end

      # Builds the find_record lambda used by row validators and hierarchy extraction.
      def build_find_record
        all_mappings = Bulkrax.field_mappings['Bulkrax::CsvParser'] || {}
        work_identifier = all_mappings.find { |_k, v| v['source_identifier'] == true }&.first || 'source'
        work_identifier_search = Array.wrap(all_mappings.dig(work_identifier, 'search_field')).first&.to_s ||
                                 "#{work_identifier}_sim"
        ->(id) { find_record_by_source_identifier(id, work_identifier, work_identifier_search) }
      end

      # Attempt to locate an existing repository record by its identifier.
      # The identifier may be a repository object ID or a source_identifier property value.
      # Checks the repository directly (by ID, then by Solr property search) — a Bulkrax
      # Entry record alone is not sufficient, as the object may never have been created.
      #
      # @param identifier [String]
      # @param work_identifier [String] the source_identifier property name (e.g. "source")
      # @param work_identifier_search [String] the Solr field for source_identifier (e.g. "source_sim")
      # @return [Boolean] true if a matching repository object is found
      def find_record_by_source_identifier(identifier, work_identifier, work_identifier_search)
        return false if identifier.blank?

        return true if Bulkrax.object_factory.find_or_nil(identifier).present?

        [Bulkrax.collection_model_class, *Bulkrax.curation_concerns].any? do |klass|
          Bulkrax.object_factory.search_by_property(
            value: identifier,
            klass: klass,
            search_field: work_identifier_search,
            name_field: work_identifier
          ).present?
        end
      rescue StandardError
        false
      end

      # Returns the raw CSV column name (String) for a relationship field.
      # Looks for the mapping entry flagged with +flag+ and returns its first +from+ value,
      # falling back to +default+ when none is found.
      def resolve_relationship_column(mappings, flag, default)
        entry = mappings.find { |_k, v| v.is_a?(Hash) && v[flag] }
        entry&.last&.dig('from')&.first || default
      end

      def resolve_parent_split_pattern(mappings)
        Bulkrax::SplitPatternCoercion.coerce(mappings.dig('parents', 'split') || mappings.dig(:parents, :split))
      end

      def resolve_children_split_pattern(mappings)
        Bulkrax::SplitPatternCoercion.coerce(mappings.dig('children', 'split') || mappings.dig(:children, :split))
      end

      # Builds a graph of { source_identifier => [parent_ids] } from all CSV records.
      # Used by CircularReference validator to detect cycles across the whole CSV.
      #
      # Parent edges are collected from both directions:
      #   - explicit parent declarations (parents / parents_N columns)
      #   - inverted child declarations (children / children_N columns), mirroring
      #     the normalisation done in importers_stepper.js#normalizeRelationships
      def build_relationship_graph(csv_data, mappings)
        parent_column   = resolve_relationship_column(mappings, 'related_parents_field_mapping', 'parents')
        children_column = resolve_relationship_column(mappings, 'related_children_field_mapping', 'children')
        parent_suffix   = /\A#{Regexp.escape(parent_column)}_\d+\z/
        children_suffix = /\A#{Regexp.escape(children_column)}_\d+\z/

        graph = build_parent_edges(csv_data, parent_suffix, resolve_parent_split_pattern(mappings))
        invert_child_edges(graph, csv_data, children_suffix, resolve_children_split_pattern(mappings))
        graph
      end

      def build_parent_edges(csv_data, suffix_pattern, split_pattern)
        csv_data.each_with_object({}) do |record, graph|
          id = record[:source_identifier]
          next if id.blank?

          base_ids = split_or_single(record[:parent], split_pattern)
          suffix_ids = suffixed_values(record[:raw_row], suffix_pattern)
          graph[id] = (base_ids + suffix_ids).uniq
        end
      end

      def invert_child_edges(graph, csv_data, suffix_pattern, split_pattern)
        csv_data.each do |record|
          id = record[:source_identifier]
          next if id.blank?

          child_ids = split_or_single(record[:children], split_pattern) +
                      suffixed_values(record[:raw_row], suffix_pattern)
          child_ids.each do |child_id|
            graph[child_id] ||= []
            graph[child_id] << id unless graph[child_id].include?(id)
          end
        end
      end

      def split_or_single(value, split_pattern)
        coerced = Bulkrax::SplitPatternCoercion.coerce(split_pattern)
        if coerced
          value.to_s.split(coerced).map(&:strip).reject(&:blank?)
        elsif value.present?
          [value.to_s.strip]
        else
          []
        end
      end

      def suffixed_values(raw_row, suffix_pattern)
        raw_row.select { |k, _| k.to_s.match?(suffix_pattern) }
               .values.map(&:to_s).map(&:strip).reject(&:blank?)
      end
    end
  end
end
