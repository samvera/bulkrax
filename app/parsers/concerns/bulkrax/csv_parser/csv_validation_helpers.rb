# frozen_string_literal: true

module Bulkrax
  class CsvParser < ApplicationParser
    # Private helper methods for CsvValidation.
    module CsvValidationHelpers # rubocop:disable Metrics/ModuleLength
      include CsvValidationHierarchy

      # Resolve a symbol key from mappings for use as a record hash key.
      # Returns a Symbol matching the parser's symbol-keyed record hash.
      #
      # With `headers:`, picks the flagged mapping's alias that appears in
      # the CSV, falling back to its first `from:` alias. Without it, uses
      # the first alias, which is the only one import reads for the source
      # identifier (ApplicationParser#source_identifier).
      def resolve_validation_key(mapping_manager, flag:, default:, headers: nil)
        if headers
          chosen = Bulkrax::FieldResolver.present_header_for_flag(mapping_manager.mappings, flag, headers)
          return chosen.to_sym if chosen
        end

        options = mapping_manager.resolve_column_name(flag: flag, default: default.to_s)
        options.first&.to_sym || default
      end

      # Parse rows from a CsvEntry.read_data result into the canonical record shape.
      # CsvEntry.read_data returns CSV::Row objects with symbol headers; blank rows
      # are already filtered by CsvWrapper.
      def parse_validation_rows(raw_csv, source_id_key, parent_key, children_key, mappings)
        file_headers  = Bulkrax::FieldResolver.headers_for_field(mappings, 'file')
        model_headers = Bulkrax::FieldResolver.headers_for_field(mappings, 'model')
        raw_csv.map do |row|
          # CSV::Row#to_h converts symbol headers → string-keyed hash
          row_hash = row.to_h.transform_keys(&:to_s)
          {
            source_identifier: row[source_id_key],
            model: row_model(row_hash, model_headers),
            parent: row[parent_key],
            children: row[children_key],
            file: row[file_headers.first.to_sym],
            file_values: row_hash.select { |header, _| Bulkrax::FieldResolver.header_for_any?(header, file_headers) }.values.reject(&:blank?),
            raw_row: row_hash
          }
        end
      rescue StandardError => e
        Rails.logger.error("CsvParser.validate_csv: error parsing rows – #{e.message}")
        []
      end

      # Matches FactoryClassFinder: every model column overwrites the parsed
      # model in CSV column order, so the last one wins when it has a value;
      # otherwise the literal `model` column, then the first alias with a value.
      def row_model(row_hash, model_headers)
        row_hash.select { |header, _| Bulkrax::FieldResolver.header_for_any?(header, model_headers) }.values.last.presence ||
          row_hash['model'].presence ||
          model_headers.map { |header| row_hash[header.to_s] }.find(&:present?)
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
        # ColumnBuilder only emits the first `from:` alias per non-property key
        # (core/file/relationship). Accept every alias so a CSV using a
        # non-primary alias like `file` (when mappings are `from: ['item', 'file']`)
        # isn't flagged unrecognised. Property-level aliases are handled
        # separately by find_unrecognized_validation_headers via mapped_to_keys.
        non_property_aliases = non_property_mapping_aliases(mappings)
        (all_cols + non_property_aliases).uniq - CsvTemplate::CsvBuilder::IGNORED_PROPERTIES
      rescue StandardError => e
        Rails.logger.error("CsvParser.validate_csv: error building valid headers – #{e.message}")
        standard = %w[model source_identifier parents children file]
        model_fields = field_metadata.values.flat_map { |m| m[:properties] }
        model_fields = model_fields.map { |prop| Bulkrax::FieldResolver.headers_for_field(mapping_manager.mappings, prop).first }
        (standard + model_fields).uniq
      end

      # Returns every `from:` alias for mapping keys that describe non-property
      # columns (core/file/relationship). These keys are fixed by the descriptor
      # rather than discovered per-model, so every alias is unambiguously valid.
      def non_property_mapping_aliases(mappings)
        descriptor = CsvTemplate::ColumnDescriptor.new
        non_property_keys = descriptor.core_columns +
                            CsvTemplate::ColumnDescriptor::COLUMN_DESCRIPTIONS[:files].flat_map(&:keys) +
                            CsvTemplate::ColumnDescriptor::COLUMN_DESCRIPTIONS[:relationships].flat_map(&:keys)
        non_property_keys.flat_map do |key|
          Bulkrax::FieldResolver.headers_for_field(mappings, key)
        end
      end

      def find_missing_required_headers(headers, field_metadata, mapping_manager)
        csv_keys = headers.flat_map do |h|
          Bulkrax::FieldResolver.fields_for_header(mapping_manager.mappings, Bulkrax::FieldResolver.key_without_numbers(h))
        end.uniq
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
          base = Bulkrax::FieldResolver.key_without_numbers(h)
          next true if valid_headers.include?(h) || valid_headers.include?(base)
          Array(mapping_manager&.mapped_to_keys(base)).any? { |key| known_property_keys.include?(key) }
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

      # Adding the default work type unconditionally makes every sheet answer
      # for that model's required fields, so a collection-only sheet gets asked
      # for properties belonging to a work type it never mentions.
      def models_to_validate(csv_data, headers, model_headers: ['model'])
        row_models = csv_data.map { |r| r[:model].to_s }.reject(&:blank?).uniq
        return row_models if Bulkrax.default_work_type.blank?
        return row_models unless default_work_type_needed?(csv_data, headers, model_headers)

        row_models | [Bulkrax.default_work_type]
      end

      def default_work_type_needed?(csv_data, headers, model_headers)
        return true unless model_column_present?(headers, model_headers)

        csv_data.empty? || csv_data.any? { |r| r[:model].blank? }
      end

      def model_column_present?(headers, model_headers)
        headers.any? { |header| Bulkrax::FieldResolver.header_for_any?(header, model_headers) }
      end

      # Adds a file-level notice when the model column is absent or every row has a blank
      # model value, indicating that the default work type will be used for all rows.
      # When this notice is present the per-row default_work_type_used warnings are
      # suppressed in the formatter — no need to repeat the same message for every row.
      def append_missing_model_notice!(notices, headers, csv_data, model_headers: ['model'])
        default_model = Bulkrax.default_work_type
        return if default_model.blank?

        model_column_present = model_column_present?(headers, model_headers)
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

      # Assembles the final result hash returned to the guided import UI.
      def assemble_result(headers:, missing_required:, header_issues:, row_errors:, csv_data:, file_validator:, collections:, works:, file_sets:, notices: []) # rubocop:disable Metrics/ParameterLists
        is_valid, has_warnings = determine_validity(
          headers: headers, missing_required: missing_required, header_issues: header_issues,
          row_errors: row_errors, csv_data: csv_data, file_validator: file_validator, notices: notices
        )

        {
          headers: headers,
          missingRequired: missing_required,
          notices: notices,
          unrecognized: header_issues[:unrecognized],
          emptyColumns: header_issues[:empty_columns],
          rowCount: csv_data.length,
          isValid: is_valid,
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

      # Returns [is_valid, has_warnings] for the assembled result.
      # rights_statement can be supplied on Step 2, so a CSV missing ONLY the
      # rights_statement column is valid-with-warnings rather than a blocker;
      # the display formatter styles that case as a warning accordion.
      def determine_validity(headers:, missing_required:, header_issues:, row_errors:, csv_data:, file_validator:, notices:) # rubocop:disable Metrics/ParameterLists
        row_error_entries   = row_errors.select { |e| e[:severity] == 'error' }
        row_warning_entries = row_errors.select { |e| e[:severity] == 'warning' }

        only_rights_missing = missing_required.present? &&
                              missing_required.all? { |h| h[:field].to_s == 'rights_statement' }
        blocking_missing_required = missing_required.any? && !only_rights_missing

        has_errors   = blocking_missing_required || headers.blank? || csv_data.empty? ||
                       file_validator.missing_files.any? || row_error_entries.any?
        has_warnings = header_issues[:unrecognized].any? || header_issues[:empty_columns].any? ||
                       file_validator.possible_missing_files? || row_warning_entries.any? ||
                       notices.any? || only_rights_missing

        [!has_errors, has_warnings]
      end

      # Builds the find_record lambda used by row validators and hierarchy extraction.
      def build_find_record
        all_mappings = Bulkrax.field_mappings['Bulkrax::CsvParser'] || {}
        flagged = Bulkrax::FieldResolver.flagged_key(all_mappings, 'source_identifier')
        work_identifier = flagged&.to_s || 'source'
        search_field = Bulkrax::FieldResolver.option(flagged && all_mappings[flagged], 'search_field')
        work_identifier_search = Array.wrap(search_field).first&.to_s || "#{work_identifier}_sim"
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

      def resolve_parent_split_pattern(mappings)
        relationship_split_pattern(mappings, 'related_parents_field_mapping', 'parents')
      end

      def resolve_children_split_pattern(mappings)
        relationship_split_pattern(mappings, 'related_children_field_mapping', 'children')
      end

      # Import splits the flagged mapping's cells, so read `split:` from that
      # mapping, falling back to the conventional key when none is flagged.
      def relationship_split_pattern(mappings, flag, default_key)
        key = Bulkrax::FieldResolver.flagged_key(mappings, flag) || default_key
        entry = mappings[key] || mappings[key.to_s] || mappings[key.to_sym]
        Bulkrax::SplitPatternCoercion.coerce(Bulkrax::FieldResolver.option(entry, 'split'))
      end

      # Builds a graph of { source_identifier => [parent_ids] } from all CSV records.
      # Used by CircularReference validator to detect cycles across the whole CSV.
      #
      # Parent edges are collected from both directions:
      #   - explicit parent declarations (parents / parents_N columns)
      #   - inverted child declarations (children / children_N columns), mirroring
      #     the normalisation done in importers_stepper.js#normalizeRelationships
      def build_relationship_graph(csv_data, mappings)
        parent_columns   = Bulkrax::CsvRow::RelationshipIds.columns(mappings, 'related_parents_field_mapping', 'parents')
        children_columns = Bulkrax::CsvRow::RelationshipIds.columns(mappings, 'related_children_field_mapping', 'children')

        graph = build_parent_edges(csv_data, parent_columns, resolve_parent_split_pattern(mappings))
        invert_child_edges(graph, csv_data, children_columns, resolve_children_split_pattern(mappings))
        graph
      end

      def build_parent_edges(csv_data, columns, split_pattern)
        csv_data.each_with_object({}) do |record, graph|
          id = record[:source_identifier]
          next if id.blank?

          graph[id] = Bulkrax::CsvRow::RelationshipIds.ids(record[:parent], record[:raw_row], columns, split_pattern)
        end
      end

      def invert_child_edges(graph, csv_data, columns, split_pattern)
        csv_data.each do |record|
          id = record[:source_identifier]
          next if id.blank?

          Bulkrax::CsvRow::RelationshipIds.ids(record[:children], record[:raw_row], columns, split_pattern).each do |child_id|
            graph[child_id] ||= []
            graph[child_id] << id unless graph[child_id].include?(id)
          end
        end
      end
    end
  end
end
