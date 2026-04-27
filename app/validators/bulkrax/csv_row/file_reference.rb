# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that every file referenced by a row will actually be
    # available to the importer after the uploaded zip is extracted.
    #
    # Reads `context[:zip_plan]` — a {Bulkrax::ZipPlacementPlanner::Plan}
    # (or any object exposing `#available_paths`) describing the set of
    # relative paths that will exist under `files/` after extraction. When
    # the plan is nil (no zip uploaded) this validator emits no errors;
    # the "files referenced but no zip" case is a run-level notice, not
    # a per-row error.
    #
    # The importer resolves a referenced path by joining it with the
    # extraction's `files/` directory and requiring that exact path to
    # exist — no basename fallback. So the validator does an exact-path
    # comparison against `plan.available_paths`. This catches cases the
    # basename-only {Bulkrax::FileValidator} silently passes, including:
    #
    # * CSV references `subdir_a/foo.jpg` but zip has `subdir_b/foo.jpg`.
    # * CSV references bare `foo.jpg` but zip has it only under
    #   `deep/nested/foo.jpg`.
    module FileReference
      def self.call(record, row_index, context)
        plan = context[:zip_plan]
        return if plan.nil?

        available = plan.available_paths.to_set

        referenced_paths(record).each do |path|
          next if available.include?(path)

          context[:errors] << error_hash(record, row_index, path)
        end
      end

      # Extracts every referenced file path from a record. `record[:file]`
      # is an Array of raw cell strings (post-Stage-1 parse_validation_rows
      # shape), and each string may itself be split by the file mapping's
      # configured `split:` pattern.
      def self.referenced_paths(record)
        Array(record[:file])
          .flat_map { |raw| raw.to_s.split(Bulkrax::CsvParser.file_split_pattern) }
          .map(&:strip)
          .reject(&:blank?)
      end
      private_class_method :referenced_paths

      def self.error_hash(record, row_index, path)
        {
          row: row_index,
          source_identifier: record[:source_identifier],
          # A referenced file missing from the ZIP is a warning, not an
          # error — the file may still exist on the server at import time.
          severity: 'warning',
          category: 'missing_file_reference',
          column: 'file',
          value: path,
          message: I18n.t('bulkrax.importer.guided_import.validation.file_reference_validator.errors.missing_file_reference.message', value: path),
          suggestion: I18n.t('bulkrax.importer.guided_import.validation.file_reference_validator.errors.missing_file_reference.suggestion')
        }
      end
      private_class_method :error_hash
    end
  end
end
