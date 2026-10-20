# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Validates that every file referenced by a row will actually be
    # available to the importer after the uploaded zip is extracted.
    #
    # Reads `context[:zip_plan]`, a {Bulkrax::ZipPlacementPlanner::Plan}
    # (or any object exposing `#available_paths`) describing the set of
    # relative paths that will exist under `files/` after extraction. When
    # the plan is nil (no zip uploaded) this validator emits no errors;
    # the "files referenced but no zip" case is a run-level notice, not
    # a per-row error.
    #
    # The importer finds a referenced file by joining it onto `files/` under
    # each of CsvParser.file_reference_candidates, after renaming each top-level entry
    # under `files/` that has a space, except names starting with `.`, which
    # the rename skips (CsvParser#remove_spaces_from_filenames).
    # There is no basename fallback, so a reference in the wrong folder is
    # an error, including:
    #
    # * CSV references `subdir_a/foo.jpg` but zip has `subdir_b/foo.jpg`.
    # * CSV references bare `foo.jpg` but zip has it only under
    #   `deep/nested/foo.jpg`.
    module FileReference
      def self.call(record, row_index, context)
        plan = context[:zip_plan]
        return if plan.nil?

        on_disk = context[:zip_paths_on_disk] ||= paths_on_disk(plan.available_paths)

        referenced_paths(record).each do |path|
          next if Bulkrax::CsvParser.file_reference_candidates(path).any? { |candidate| on_disk.include?(candidate.b) }

          context[:errors] << error_hash(record, row_index, path)
        end
      end

      def self.paths_on_disk(available_paths)
        available_paths.map do |path|
          top, rest = path.split('/', 2)
          top = top.tr(' ', '_') unless top.start_with?('.')
          [top, rest].compact.join('/').b
        end.to_set
      end
      private_class_method :paths_on_disk

      # Each cell in `record[:file_values]` may itself be split by the file
      # `split:` pattern.
      def self.referenced_paths(record)
        Array(record[:file_values])
          .flat_map { |raw| raw.to_s.split(Bulkrax::CsvParser.file_split_pattern) }
          .map(&:strip)
          .reject(&:blank?)
      end
      private_class_method :referenced_paths

      def self.error_hash(record, row_index, path)
        {
          row: row_index,
          source_identifier: record[:source_identifier],
          severity: 'error',
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
