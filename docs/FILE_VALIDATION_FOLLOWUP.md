# File Reference Validation — Follow-up Plan

## Context

Guided-import validation currently uses `Bulkrax::CsvTemplate::FileValidator` to
check whether files referenced in a CSV exist inside an uploaded zip. The check
compares **basenames only** (`File.basename`), ignoring relative paths.

During the CSV unzip/extraction fix (issue #609, `i609-typeerror-on-unzip`), we
established that `CsvParser#path_to_files` resolves CSV `file:` column values as
**relative paths** under `files/`. So a CSV row with `file: "subdir/foo.jpg"`
requires `importer_unzip_path/files/subdir/foo.jpg` at import time. The
validator's basename-only comparison misses real errors:

1. **Subdirectory mismatch** — CSV references `subdir_a/foo.jpg`; zip contains
   `subdir_b/foo.jpg`. Basenames match, validator passes, import 404s.
2. **Root/nested mismatch** — CSV references `foo.jpg`; zip contains
   `deep/nested/foo.jpg`. Validator passes, import 404s.
3. **Ambiguous basenames** — CSV references `foo.jpg`; zip contains both
   `dir_a/foo.jpg` and `dir_b/foo.jpg`. Validator passes silently.
4. **Case sensitivity** — `Foo.jpg` vs `foo.jpg` on case-sensitive filesystems
   (most Hyku deployments).

Validation gives a false-positive "valid" and the job fails later at import
time with an unhelpful missing-file error.

## Architectural decision

File validation moves from the standalone `CsvTemplate::FileValidator` class
into the existing `Bulkrax::CsvRow::*` row-validator framework. Reasoning:

- Row validators are pluggable via `Bulkrax.csv_row_validators` — apps can
  register custom validators. `FileValidator` is hard-referenced in
  `CsvValidation#run_validations` with no extension point.
- Row validators produce uniform errors `{row, source_identifier, severity,
  category, column, value, message, suggestion}` that flow through
  `StepperResponseFormatter` and `ValidationErrorCsvBuilder` consistently. The
  current `FileValidator` has a parallel code path and a different output
  shape (flat `missingFiles` basename list with no row attribution).
- Per-row errors are strictly more informative than aggregated basename lists:
  users see which row references which missing file, not just the union.
- Path-awareness is natural: each row validator sees `record[:file]` and can
  compare full relative paths against a shared plan passed in via `context`.

## Prerequisites from the extraction fix

The extraction fix (prior work on this branch) introduces a placement planner
that, given a zip's entry list and a mode (`primary_csv` vs
`attachments_only`), returns a mapping of `zip_entry_name →
post_extraction_relative_path`. The planner is shared by:

- `CsvParser#unzip_with_primary_csv` / `#unzip_attachments_only` — execute the
  plan by extracting each entry to its planned path.
- This follow-up — predicts the set of relative paths that will be available
  under `files/`, for validation.

The planner exposes a read-only method (shape tbd) like:

```ruby
plan.available_paths  # => Set<String> of relative paths under files/
                       #    e.g. #<Set: {"foo.jpg", "subdir/bar.pdf"}>
```

If the extraction fix lands without a named planner class (inline logic in
`CsvParser#unzip_*`), the first step of this follow-up is to extract it.

## Plan

### 1. Extract or expose the placement planner

Ensure the zip-placement logic is accessible from outside the unzip methods.
Expected interface:

```ruby
plan = Bulkrax::ZipPlacementPlanner.plan(zip_file_path, mode: :primary_csv)
plan.primary_csv_entry     # => Zip::Entry or nil
plan.available_paths       # => Set<String> relative paths that will exist under files/
plan.errors                # => Array<Symbol> of error codes: :no_csv, :multiple_csv_same_level, ...
```

Modes:
- `:primary_csv` — zip contains the CSV. Applies shallowest-CSV rule.
- `:attachments_only` — zip has no CSV. Applies single-top-level-wrapper strip.

Errors from the planner (e.g. multi-CSV-at-shallowest) become validation
errors in the new flow — they're the same errors `locate_csv_entry_in_zip`
raises today.

### 2. Build `context[:zip_plan]`

In `CsvValidation#run_row_validators`, build `zip_plan` once per validation
run and add it to the context hash. The planner runs once; every row uses the
same plan.

```ruby
context[:zip_plan] = zip_file ? Bulkrax::ZipPlacementPlanner.plan(zip_file.path, mode: inferred_mode) : nil
```

Mode is inferred from the upload shape:
- User uploaded CSV + zip → `:attachments_only`.
- User uploaded zip only → `:primary_csv`.

### 3. Add `Bulkrax::CsvRow::FileReference` row validator

New file: `app/validators/bulkrax/csv_row/file_reference.rb`.

```ruby
module Bulkrax
  module CsvRow
    module FileReference
      def self.call(record, row_index, context)
        plan = context[:zip_plan]
        return if plan.nil?  # no zip uploaded

        value = record[:file]
        return if value.blank?

        value.split(Bulkrax.multi_value_element_split_on).each do |raw|
          path = raw.strip
          next if path.blank?
          next if plan.available_paths.include?(path)

          context[:errors] << missing_file_error(record, row_index, path, plan)
        end
      end

      # emits either :missing_file_reference or :ambiguous_basename depending
      # on whether `path` is a bare basename that matches multiple entries
      def self.missing_file_error(...); end
    end
  end
end
```

Register in defaults at [lib/bulkrax.rb](../lib/bulkrax.rb#L182):

```ruby
def csv_row_validators
  @csv_row_validators ||= [
    Bulkrax::CsvRow::MissingSourceIdentifier,
    Bulkrax::CsvRow::DuplicateIdentifier,
    Bulkrax::CsvRow::ParentReference,
    Bulkrax::CsvRow::ChildReference,
    Bulkrax::CsvRow::CircularReference,
    Bulkrax::CsvRow::RequiredValues,
    Bulkrax::CsvRow::ControlledVocabulary,
    Bulkrax::CsvRow::FileReference   # ← new
  ]
end
```

### 4. Handle distinct error categories

Emit different `category:` values so the UI and error CSV can distinguish:

- `missing_file_reference` — path not found in plan.
- `ambiguous_basename` — CSV used a bare basename that matches multiple
  entries in the plan under different paths.
- `case_mismatch` — plan has a matching path with different casing.
  (Optional — costs a second scan; decide based on user demand.)

Each category gets its own i18n entry under
`bulkrax.importer.guided_import.validation.file_reference_validator.errors.*`.

### 5. Retire `CsvTemplate::FileValidator`

Delete `app/services/bulkrax/csv_template/file_validator.rb` or reduce to a
stats helper that answers:

- `zip_included?`
- `count_references` (how many rows reference files, regardless of missing)

These are run-level observations, not validation errors. Keep as a small
helper; remove the `missing_files` / `possible_missing_files?` /
`found_files_count` methods, which are superseded by row errors.

Update [csv_validation.rb:54](../app/parsers/concerns/bulkrax/csv_parser/csv_validation.rb#L54)
to stop instantiating `FileValidator` for correctness purposes. The
`assemble_result` call that currently passes `file_validator:` downstream
either drops the key or retains it for the stats it still produces.

### 6. Update `StepperResponseFormatter`

Current special handling at [stepper_response_formatter.rb:238-261](../app/services/bulkrax/stepper_response_formatter.rb#L238-L261):

```ruby
missing_files = @data[:missingFiles] || []
if missing_files.any? && @data[:zipIncluded]
  missing_files_issue
  ...
```

This block either goes away (errors flow through normal row-errors pipe) or
becomes a derived summary ("N rows reference missing files") computed from
grouping row errors with `category: 'missing_file_reference'`. Decide based on
UI needs — per-row errors are clearer, but an aggregate "N files missing"
headline may still be wanted for quick scan.

### 7. Update `ValidationErrorCsvBuilder`

The builder already handles row errors uniformly
([validation_error_csv_builder.rb:92](../app/services/bulkrax/validation_error_csv_builder.rb#L92)).
Missing-file errors now arrive as row errors, so the CSV output should
automatically include them. Verify via spec.

Remove the special `missing_files` handling at line 92 if it was reading from
the old flat list.

### 8. "No zip but files referenced" warning

Keep this as a run-level **notice**, not a row error. Similar to
`append_missing_model_notice!`:

```ruby
def append_missing_zip_notice!(notices, csv_data)
  return if csv_data.none? { |r| r[:file].present? }
  return if zip_present?
  notices << {
    field: 'file',
    category: 'files_referenced_no_zip',
    message: I18n.t(...)
  }
end
```

Called from `run_validations` before the row loop runs.

### 9. Spec coverage

New spec files:
- `spec/validators/bulkrax/csv_row/file_reference_spec.rb` — unit coverage for
  the new row validator, covering:
  - No zip plan → no errors (nothing to validate against).
  - Simple basename match in plan → no error.
  - Path match in plan → no error.
  - Path mismatch → error with category `missing_file_reference`.
  - Multi-value cell with one missing → one error for the missing value.
  - Ambiguous basename → error with category `ambiguous_basename`.
  - Case mismatch (if implemented) → error with category `case_mismatch`.
- `spec/services/bulkrax/zip_placement_planner_spec.rb` — unit coverage for
  the planner, assuming it was extracted as a standalone class by the
  extraction fix.

Update existing:
- `spec/parsers/concerns/bulkrax/csv_parser/csv_validation_spec.rb` — end-to-end
  flows using the new row validator.
- `spec/services/bulkrax/stepper_response_formatter_spec.rb` — adjust to new
  formatter output.
- `spec/services/bulkrax/validation_error_csv_builder_spec.rb` — verify
  missing-file errors appear in the CSV output.

Delete:
- `spec/services/bulkrax/csv_template/file_validator_spec.rb` (or pare down to
  match the reduced helper, if kept).

### 10. Backwards compatibility

Apps overriding `Bulkrax.csv_row_validators` to a custom array will not pick
up the new validator automatically. Document in the changelog:

> To get file-reference validation, append
> `Bulkrax::CsvRow::FileReference` to your custom `csv_row_validators` array,
> or call `Bulkrax.register_csv_row_validator(Bulkrax::CsvRow::FileReference)`.

Apps relying on `result[:missingFiles]` in the validation response need to
migrate to reading row errors with `category: 'missing_file_reference'`. Call
out in release notes.

## Effort estimate

- Placement planner extraction (if not done by extraction fix): 2-3 hours.
- Row validator + registration + i18n: 2-3 hours.
- Stepper/CsvBuilder updates: 1-2 hours.
- Spec coverage: 3-4 hours.
- **Total: roughly 1 day**, assuming the extraction fix has already produced
  a shareable placement planner.

## Out of scope for this follow-up

- Validation of file *contents* (size, checksum, format).
- Validation that the zip itself is a valid archive — already handled
  upstream.
- Cloud-files flow — `retrieve_cloud_files` places files directly into
  `files/` at upload time, no zip plan involved. If cloud-files need path
  validation, that's a separate piece.

## Open questions to resolve before implementing

1. Does the placement planner emerge as a named class from the extraction
   fix, or does it need to be factored out as step 1 of this follow-up?
2. Does the UI want to keep an aggregate "N files missing" headline, or go
   fully row-by-row?
3. Should `case_mismatch` be its own category, or lumped into
   `missing_file_reference` with a more specific message?
