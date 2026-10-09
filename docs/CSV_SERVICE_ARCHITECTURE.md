# CSV Architecture

## Overview

CSV template generation and validation are implemented as concerns on `CsvParser`, supported by a set of focused service classes under `Bulkrax::CsvTemplate::` and callable validator modules under `Bulkrax::CsvRow::`.

## Public API

### Template Generation

```ruby
CsvParser.generate_template(models: 'all', output: 'file', admin_set_id: 'default')
# => String (file path)

CsvParser.generate_template(models: ['GenericWork'], output: 'csv_string')
# => String (CSV content)
```

### Validation

```ruby
result = CsvParser.validate_csv(csv_file: csv_file, zip_file: zip_file, admin_set_id: 'default')
```

Returns:

```ruby
{
  headers: [...],              # Column names in CSV
  missingRequired: [...],      # [{model: 'Work', field: 'title'}, ...]
  unrecognized: {              # Unrecognized columns mapped to spell-check suggestions
    'creatir' => 'creator',
    'unknwon' => nil
  },
  rowCount: 247,
  isValid: true,
  hasWarnings: false,
  rowErrors: [...],            # Row-level errors from CsvRow:: validators
  collections: [...],
  works: [...],
  fileSets: [...],
  totalItems: 247,
  fileReferences: 55,
  missingFiles: [...],
  foundFiles: 52,
  zipIncluded: true
}
```

**Rights Statement Special Case:** When the only missing required field is `rights_statement`, `assemble_result` reports the CSV as valid with a warning (rather than invalid). This supports workflows where rights statements are assigned on the next step via the default rights statement selector.

## Architecture

### Template Generation

```
CsvParser.generate_template
  └── CsvParser::CsvTemplateGeneration (concern)
        └── TemplateContext
              ├── CsvTemplate::MappingManager   - Field mapping resolution
              ├── CsvTemplate::FieldAnalyzer    - Schema introspection (cached per model)
              ├── CsvTemplate::ModelLoader      - Loads model classes from Hyrax / constantize
              └── CsvTemplate::CsvBuilder       - Writes CSV file or string
                    ├── CsvTemplate::RowBuilder       - Creates header, explanation, and data rows
                    │     ├── CsvTemplate::ValueDeterminer    - Sample cell values
                    │     └── CsvTemplate::ExplanationBuilder - Field descriptions
                    ├── CsvTemplate::ColumnBuilder    - Assembles valid column list
                    │     ├── CsvTemplate::ColumnDescriptor   - Core column definitions
                    │     └── CsvTemplate::SplitFormatter     - Multi-value delimiter descriptions
                    ├── CsvTemplate::SchemaAnalyzer   - Property extraction from model schemas
                    └── CsvTemplate::FilePathGenerator - Default output paths
```

### Validation

```
CsvParser.validate_csv
  └── CsvParser::CsvValidation (concern)
        ├── CsvEntry.read_data              - CSV parsing with blank-row filtering
        ├── CsvTemplate::MappingManager     - Resolve column names from field mappings
        ├── CsvTemplate::FieldAnalyzer      - Required fields, controlled vocab per model
        ├── CsvTemplate::ColumnBuilder      - Valid headers for comparison
        ├── CsvTemplate::FileValidator      - File references vs zip contents
        ├── Bulkrax.csv_row_validators      - Array of callable row validators
        │     ├── CsvRow::DuplicateIdentifier
        │     ├── CsvRow::ParentReference
        │     ├── CsvRow::RequiredValues
        │     └── CsvRow::ControlledVocabulary
        └── DidYouMean::SpellChecker        - Suggestions for unrecognized columns
```

### Key Detail: CSV Parsing

`CsvParser::CsvValidation` uses `CsvEntry.read_data` (not `CSV.read`) to parse the uploaded file. This ensures blank rows are filtered in the same way as a real import, so `rowCount` and field extraction match what the importer will actually process.

Rows are `CSV::Row` objects with symbol-keyed headers. Field access uses the symbol key directly (e.g. `row[:source_identifier]`). `raw_row` is built via `row.to_h.transform_keys(&:to_s)`.

## File Locations

### Concerns

| File | Purpose |
|------|---------|
| `app/parsers/concerns/bulkrax/csv_parser/csv_template_generation.rb` | `generate_template` + `TemplateContext` |
| `app/parsers/concerns/bulkrax/csv_parser/csv_validation.rb` | `validate_csv` |

### CsvTemplate:: Service Classes

| File | Purpose |
|------|---------|
| `app/services/bulkrax/csv_template/mapping_manager.rb` | Field mapping resolution |
| `app/services/bulkrax/csv_template/field_analyzer.rb` | Schema introspection (cached) |
| `app/services/bulkrax/csv_template/schema_analyzer.rb` | Property extraction from model schemas |
| `app/services/bulkrax/csv_template/model_loader.rb` | Load and validate model classes |
| `app/services/bulkrax/csv_template/column_builder.rb` | Assemble valid column list |
| `app/services/bulkrax/csv_template/column_descriptor.rb` | Core column names and descriptions |
| `app/services/bulkrax/csv_template/csv_builder.rb` | Generate CSV file or string |
| `app/services/bulkrax/csv_template/row_builder.rb` | Header, explanation, and data rows |
| `app/services/bulkrax/csv_template/value_determiner.rb` | Sample cell values |
| `app/services/bulkrax/csv_template/explanation_builder.rb` | Field help text |
| `app/services/bulkrax/csv_template/split_formatter.rb` | Multi-value delimiter descriptions |
| `app/services/bulkrax/csv_template/file_path_generator.rb` | Default output file paths |
| `app/services/bulkrax/csv_template/file_validator.rb` | Validate file references vs zip |

### CsvRow:: Validator Modules

| File | Category | Severity |
|------|----------|----------|
| `app/validators/bulkrax/csv_row/duplicate_identifier.rb` | `duplicate_source_identifier` | error |
| `app/validators/bulkrax/csv_row/parent_reference.rb` | `invalid_parent_reference` | error |
| `app/validators/bulkrax/csv_row/required_values.rb` | `missing_required_value` | error |
| `app/validators/bulkrax/csv_row/controlled_vocabulary.rb` | `invalid_controlled_value` | error |

### Related Files

| File | Purpose |
|------|---------|
| `app/controllers/bulkrax/guided_imports_controller.rb` | Calls `CsvParser.validate_csv`, delegates to `StepperResponseFormatter` |
| `app/controllers/bulkrax/importers_controller.rb` | Calls `CsvParser.generate_template` for template download |
| `app/services/bulkrax/stepper_response_formatter.rb` | Formats validation results for the stepper UI |

## Configuration

### csv_row_validators

`Bulkrax.csv_row_validators` is an array of callable objects (modules/classes responding to `.call`). Each is called once per row during validation.

Default value (set in `lib/bulkrax.rb`):

```ruby
Bulkrax.csv_row_validators
# => [
#   Bulkrax::CsvRow::DuplicateIdentifier,
#   Bulkrax::CsvRow::ParentReference,
#   Bulkrax::CsvRow::RequiredValues,
#   Bulkrax::CsvRow::ControlledVocabulary
# ]
```

### Adding a Custom Row Validator

Register a callable that responds to `.call(record, row_number, context)`:

```ruby
# config/initializers/bulkrax.rb
Bulkrax.config do |config|
  config.register_csv_row_validator(MyCustomRowValidator)
end
```

Or replace the array entirely:

```ruby
Bulkrax.config do |config|
  config.csv_row_validators = [MyValidator, AnotherValidator]
end
```

### CsvRow:: Callable Interface

Each validator receives:

| Parameter | Type | Description |
|-----------|------|-------------|
| `record` | Hash | Parsed row with `:source_identifier`, `:model`, `:parent`, `:children`, `:file`, `:raw_row` |
| `row_number` | Integer | 1-indexed row number (accounting for header row) |
| `context` | Hash | Shared validation context |

Context keys available to validators:

| Key | Type | Description |
|-----|------|-------------|
| `:errors` | Array | Append error hashes here |
| `:seen_ids` | Hash | `source_identifier => row_number` for duplicate detection |
| `:all_ids` | Set | All source identifiers in the CSV |
| `:field_metadata` | Hash | Per-model required and controlled vocab fields |
| `:mapping_manager` | `CsvTemplate::MappingManager` | Field mapping resolver |

### Error Hash Structure

Each error appended to `context[:errors]` must follow this structure:

| Key | Type | Description |
|-----|------|-------------|
| `row` | Integer | 1-indexed row number |
| `source_identifier` | String | The record's source identifier |
| `severity` | String | `'error'` or `'warning'` |
| `category` | String | Machine-readable category |
| `column` | String | CSV column name affected |
| `value` | String | The cell value that triggered the issue |
| `message` | String | Human-readable description |
| `suggestion` | String\|nil | Actionable fix suggestion, or `nil` |

## Component Details

### MappingManager

Resolves Bulkrax field mappings between internal keys and CSV column names.

```ruby
manager = CsvTemplate::MappingManager.new
manager.mapped_to_key('work_type')       # => 'model'
manager.key_to_mapped_column('model')    # => 'work_type'
```

### FieldAnalyzer

Extracts and caches field metadata for model classes. Handles both Valkyrie (schema) and ActiveFedora (properties.keys) models.

```ruby
analyzer = CsvTemplate::FieldAnalyzer.new(mappings, admin_set_id)
analyzer.find_or_create_field_list_for(model_name: 'GenericWork')
# => { properties: [...], required_terms: ['title'], controlled_vocab_terms: [...] }
```

### ModelLoader

Loads model classes by name. Supports both `resource_class_resolver` (Valkyrie) and `constantize` (ActiveFedora). When `models` is empty or `'all'`, loads all models from `Hyrax.config.curation_concerns`.

```ruby
loader = CsvTemplate::ModelLoader.new(['GenericWork', 'Collection'])
loader.models  # => ['GenericWork', 'Collection']

CsvTemplate::ModelLoader.determine_klass_for('GenericWork')  # => GenericWork (class)
```

### ColumnBuilder

Assembles the full list of valid CSV columns for a set of models. Combines core columns from `ColumnDescriptor`, relationship columns (parents/children), and file columns. All names are resolved through `MappingManager`.

### FileValidator

Validates file references in parsed CSV data against the contents of an uploaded ZIP archive. Compares basenames only (no path comparison).

```ruby
validator = CsvTemplate::FileValidator.new(csv_data, zip_file, admin_set_id)
validator.count_references       # => 10
validator.missing_files          # => ['image1.jpg']
validator.found_files_count      # => 9
validator.zip_included?          # => true
validator.possible_missing_files? # => false
```

### TemplateContext

The `TemplateContext` class (nested inside `CsvParser::CsvTemplateGeneration`) wires the template-generation components together. It holds the `all_models`, `mappings`, `field_analyzer`, and `mapping_manager` attributes that `CsvTemplate::ColumnBuilder` and others read during generation.
