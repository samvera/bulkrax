# CSV Validation Service Architecture

## Overview

The `CsvValidationService` is a unified service that handles both CSV template generation and CSV validation for Bulkrax imports. It provides a single, cohesive interface for all CSV-related operations.

## Architecture

### Two Operating Modes

The service operates in two distinct modes based on initialization parameters:

#### 1. Generation Mode
```ruby
service = CsvValidationService.new(models: ['GenericWork', 'Collection'])
# OR
CsvValidationService.generate_template(models: 'all', output: 'file', admin_set_id: 'default')
```

**Purpose:** Create sample CSV templates showing valid structure and fields

**Key Components Used:**
- `ModelLoader` - Loads specified models or all available models
- `FieldAnalyzer` - Extracts schema information from models
- `SchemaAnalyzer` - Introspects Valkyrie/ActiveFedora model schemas
- `ColumnBuilder` - Assembles valid column names
- `ColumnDescriptor` - Defines core columns and their descriptions
- `CsvBuilder` - Generates CSV content
- `RowBuilder` - Creates sample data rows
- `ValueDeterminer` - Determines sample values for cells
- `ExplanationBuilder` - Adds helpful descriptions
- `SplitFormatter` - Formats multi-value split patterns
- `FilePathGenerator` - Generates default output file paths

#### 2. Validation Mode
```ruby
service = CsvValidationService.new(csv_file: csv_file, zip_file: zip_file, admin_set_id: 'default')
# OR
CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file, admin_set_id: 'default')
```

**Purpose:** Validate uploaded CSV files against model schemas

**Key Components Used:**
- `CsvParser` - Parses CSV files, extracts headers and structured data
- `ColumnResolver` - Resolves CSV column names from Bulkrax field mappings
- `Validator` - Validates headers, checks required fields, identifies unrecognized columns with spell-check suggestions
- `FileValidator` - Validates file references against zip archive
- `ItemExtractor` - Extracts and categorizes collections, works, and file sets
- `FieldAnalyzer` - Gets required fields, controlled vocab, etc. (shared)
- `SchemaAnalyzer` - Property extraction (shared)
- `ColumnBuilder` - Determines valid headers (shared)
- `MappingManager` - Resolves field mappings (shared)

## Component Architecture

The service is composed of 18 specialized subclasses (plus 5 row validator subclasses) organized by responsibility:

```
┌───────────────────────────────────────────────────────────────────┐
│                    CsvValidationService 
│
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │        Common Components (Both Modes)                       │  │
│  │                                                             │  │
│  │  • MappingManager (78 lines)    - Field mapping resolution  │  │
│  │  • FieldAnalyzer (54 lines)     - Schema introspection      │  │
│  │  • SchemaAnalyzer (72 lines)    - Property extraction       │  │
│  │  • ModelLoader (42 lines)       - Model loading/validation  │  │
│  │  • ColumnBuilder (58 lines)     - Valid column assembly     │  │
│  │  • ColumnDescriptor (56 lines)  - Core column definitions   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────┐  ┌────────────────────────────────┐ │
│  │  Generation Mode         │  │   Validation Mode              │ │
│  │                          │  │                                │ │
│  │  • CsvBuilder (82 lines) │  │  • CsvParser (109 lines)       │ │
│  │  • RowBuilder (33 lines) │  │  • ColumnResolver (92 lines)   │ │
│  │  • ExplanationBuilder    │  │  • Validator (112 lines)       │ │
│  │    (51 lines)            │  │  • FileValidator (103 lines)   │ │
│  │  • ValueDeterminer       │  │  • ItemExtractor (177 lines)   │ │
│  │    (67 lines)            │  │  • RowValidatorService         │ │
│  │  • SplitFormatter        │  │    (54 lines + 5 subclasses)   │ │
│  │    (42 lines)            │  │                                │ │
│  │  • FilePathGenerator     │  │                                │ │
│  │    (45 lines)            │  │                                │ │
│  └──────────────────────────┘  └────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

## Key Methods

### Public API

#### Template Generation
```ruby
# Class method
CsvValidationService.generate_template(models: ['Work'], output: 'file', admin_set_id: 'default')

# Instance methods
service = CsvValidationService.new(models: ['Work'], admin_set_id: 'default')
service.to_file(file_path: 'path/to/file.csv')
service.to_csv_string
```

#### Validation
```ruby
# Class method
result = CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file, admin_set_id: 'default')

# Returns:
{
  headers: [...],              # Column names in CSV
  missingRequired: [...],      # Missing required fields [{model: 'Work', field: 'title'}]
  unrecognized: {              # Unrecognized columns mapped to spell-check suggestions
    'creatir' => 'creator',    #   (uses DidYouMean::SpellChecker)
    'unknwon' => nil
  },
  rowCount: 247,               # Total rows
  isValid: true/false,         # Overall validity
  hasWarnings: true/false,     # Has warnings
  collections: [...],          # Collection items with parentIds and childIds
  works: [...],                # Work items with parentIds and childIds
  fileSets: [...],             # File set items
  totalItems: 247,             # Total count
  fileReferences: 55,          # File refs in CSV
  missingFiles: [...],         # Files not in zip
  foundFiles: 52,              # Files in zip
  zipIncluded: true/false      # Zip provided
}
```

**Rights Statement Override:** When the only missing required field is `rights_statement`, and there are no missing files, the service treats the CSV as valid with a warning rather than invalid. This supports workflows where rights statements are assigned after import.

### Shared Analysis Methods

```ruby
service = CsvValidationService.new(models: ['Work'], admin_set_id: 'default')

# Get field metadata for all models
metadata = service.field_metadata_for_all_models
# Returns:
# {
#   'Work' => {
#     properties: ['title', 'creator', ...],
#     required_terms: ['title'],
#     controlled_vocab_terms: ['subject', 'language']
#   }
# }

# Get all valid headers
headers = service.valid_headers_for_models
# Returns: ['model', 'source_identifier', 'title', 'creator', ...]
```

## Data Flow

### Generation Mode Flow
```
1. Initialize with models (and optional admin_set_id)
2. ModelLoader loads model classes (from Hyrax curation concerns)
3. FieldAnalyzer + SchemaAnalyzer extract schema for each model
4. ColumnBuilder + ColumnDescriptor assemble valid columns
5. RowBuilder + ValueDeterminer create sample rows
6. ExplanationBuilder + SplitFormatter add field descriptions
7. CsvBuilder writes to file/string (removing empty columns)
8. FilePathGenerator provides default path if none specified
```

### Validation Mode Flow
```
1. Initialize with csv_file (+ optional zip_file, admin_set_id)
2. Create ColumnResolver with MappingManager
3. Create CsvParser → parses CSV, extracts headers and data (including parent and children columns)
4. CsvParser extracts unique models from CSV
5. Create FileValidator → analyzes zip contents
6. Create ItemExtractor → categorizes CSV rows and resolves bidirectional parent-child relationships
7. FieldAnalyzer + SchemaAnalyzer get schema for found models
8. ColumnBuilder builds valid headers for comparison
9. Create Validator → compares headers, checks required fields, spell-checks unrecognized columns
10. Apply rights_statement override if applicable
11. Return comprehensive validation results with resolved relationships
```

## Subclass Reference

### Common Components

#### 1. MappingManager
**Location:** `app/services/bulkrax/csv_validation_service/mapping_manager.rb`

**Responsibility:** Resolve Bulkrax field mappings between internal keys and CSV column names

**Key Methods:**
- `mapped_to_key(column_str)` - Convert CSV column name to internal field key
- `key_to_mapped_column(key)` - Convert internal field key to CSV column name
- `find_by_flag(field_name, default)` - Find mapping by flag (e.g., source_identifier flag)
- `split_value_for(mapping_key)` - Get split delimiter for multi-value fields
- `resolve_column_name(key:, flag:, default:)` - Generic column name lookup with multiple strategies

**Example:**
```ruby
manager = MappingManager.new
manager.mapped_to_key('work_type')       # => 'model'
manager.key_to_mapped_column('model')    # => 'work_type'
```

#### 2. FieldAnalyzer
**Location:** `app/services/bulkrax/csv_validation_service/field_analyzer.rb`

**Responsibility:** Extract and cache field metadata for models

**Key Methods:**
- `find_or_create_field_list_for(model_name:)` - Get field metadata for a model (cached)
- `controlled_vocab_terms` - Get all controlled vocabulary field names

**Details:** Handles both Valkyrie (schema) and ActiveFedora (properties.keys) models. Delegates schema introspection to `SchemaAnalyzer`.

#### 3. SchemaAnalyzer
**Location:** `app/services/bulkrax/csv_validation_service/schema_analyzer.rb`

**Responsibility:** Introspect Valkyrie model schemas for required and controlled vocabulary fields

**Key Methods:**
- `required_terms` - Get required field names (checks `form.required` metadata)
- `controlled_vocab_terms` - Get controlled vocabulary field names (checks `controlled_values.sources`)

**Details:** Uses `Hyrax.schema_for` when available for context-gated properties (respects admin_set_id). Falls back to `Qa::Authorities::Local` registry for file-based authorities.

#### 4. ModelLoader
**Location:** `app/services/bulkrax/csv_validation_service/model_loader.rb`

**Responsibility:** Load and validate model classes

**Key Methods:**
- `models` (attr_reader) - Returns loaded model name strings
- `self.determine_klass_for(model_name)` - Load a model class by name

**Details:** Supports both Valkyrie (`resource_class_resolver`) and ActiveFedora (`constantize`) object factories. Loads all available models from `Hyrax.config.curation_concerns` when models is empty or `'all'`.

#### 5. ColumnBuilder
**Location:** `app/services/bulkrax/csv_validation_service/column_builder.rb`

**Responsibility:** Assemble complete lists of valid CSV columns

**Key Methods:**
- `all_columns` - Returns all valid CSV columns for the model(s)
- `required_columns` - Returns only required Bulkrax columns (core + relationship + file columns)

**Details:** Combines core columns from `ColumnDescriptor`, relationship columns (children/parents) from flag-based mappings, and file columns. Maps all column names through `MappingManager`.

#### 6. ColumnDescriptor
**Location:** `app/services/bulkrax/csv_validation_service/column_descriptor.rb`

**Responsibility:** Define core column names and their human-readable descriptions

**Key Methods:**
- `core_columns` - Returns essential column names
- `find_description_for(column)` - Returns help text for a column

**Details:** Maintains `COLUMN_DESCRIPTIONS` constant organized into groups: `include_first`, `visibility`, `files`, `relationships`, and `other`.

### Generation Mode Components

#### 7. CsvBuilder
**Location:** `app/services/bulkrax/csv_validation_service/csv_builder.rb`

**Responsibility:** Generate CSV template files

**Key Methods:**
- `write_to_file(file_path)` - Write CSV template to file
- `generate_string` - Return CSV template as string

**Details:** Maintains `IGNORED_PROPERTIES` constant (23 properties like `admin_set_id`, `created_at`, `file_ids`, etc.). Builds rows: headers, explanation row, and model-specific data rows. Removes empty columns for clean templates.

#### 8. RowBuilder
**Location:** `app/services/bulkrax/csv_validation_service/row_builder.rb`

**Responsibility:** Create rows for CSV templates

**Key Methods:**
- `build_explanation_row(header_row)` - Generate row with field descriptions
- `build_model_rows(header_row)` - Generate sample data rows for each model

**Details:** Uses `ValueDeterminer` to populate cells and `ExplanationBuilder` for descriptions.

#### 9. ValueDeterminer
**Location:** `app/services/bulkrax/csv_validation_service/value_determiner.rb`

**Responsibility:** Determine appropriate sample values for CSV template cells

**Key Methods:**
- `determine_value(column, model_name, field_list)` - Get sample value for a CSV cell

**Details:** Returns "Required", "Optional", or specific sample values for special columns (model names, work types, visibility, rights statements). Marks file columns as Optional for collections.

#### 10. ExplanationBuilder
**Location:** `app/services/bulkrax/csv_validation_service/explanation_builder.rb`

**Responsibility:** Generate human-readable explanation rows for CSV templates

**Key Methods:**
- `build_explanations(header_row)` - Generate explanation row for CSV headers

**Details:** Combines column descriptions, controlled vocabulary info, and split patterns. Uses `SplitFormatter` for multi-value delimiter descriptions.

#### 11. SplitFormatter
**Location:** `app/services/bulkrax/csv_validation_service/split_formatter.rb`

**Responsibility:** Convert regex split patterns to human-readable text

**Key Methods:**
- `format(split_value)` - Convert regex patterns to instructions like "Split multiple values with |"

#### 12. FilePathGenerator
**Location:** `app/services/bulkrax/csv_validation_service/file_path_generator.rb`

**Responsibility:** Generate default file paths for template output

**Key Methods:**
- `self.default_path(admin_set_id)` - Generate default template file path

**Details:** Generates paths in `tmp/imports/` directory. Includes context and tenant information in filename. Supports multi-tenant (Apartment) environments.

### Validation Mode Components

#### 13. CsvParser
**Location:** `app/services/bulkrax/csv_validation_service/csv_parser.rb`

**Responsibility:** Parse CSV files and extract structured data

**Key Methods:**
- `headers` - Returns array of CSV column names
- `extract_models` - Extracts unique model names from CSV
- `parse_data` - Parses CSV into structured hashes

**Returns structured data with keys:** `source_identifier`, `model`, `parent`, `children`, `file`, `raw_row`

**Example:**
```ruby
parser = CsvParser.new(csv_file, column_resolver)
parser.headers          # => ['model', 'title', 'creator', 'parents', 'children']
parser.extract_models   # => ['GenericWork', 'Collection']
parser.parse_data       # => [{source_identifier: 'work1', model: 'GenericWork', parent: 'col1', ...}]
```

#### 14. ColumnResolver
**Location:** `app/services/bulkrax/csv_validation_service/column_resolver.rb`

**Responsibility:** Resolve CSV column names from Bulkrax field mappings

**Key Methods:**
- `model_column_name(csv_headers)` - Finds the column used for model/work type
- `source_identifier_column_name(csv_headers)` - Finds the source identifier column
- `parent_column_name(csv_headers)` - Finds the parent relationships column
- `children_column_name(csv_headers)` - Finds the children relationships column
- `file_column_name(csv_headers)` - Finds the file reference column

**Why It's Needed:** Bulkrax allows custom field mappings, so the CSV might use `work_type` instead of `model`, or `source_id` instead of `source_identifier`. This class delegates to `MappingManager.resolve_column_name` to check which mapped name actually exists in the CSV headers.

**Example:**
```ruby
resolver = ColumnResolver.new(mapping_manager)
resolver.model_column_name(['work_type', 'title'])               # => 'work_type'
resolver.source_identifier_column_name(['source_id', 'title'])   # => 'source_id'
```

#### 15. Validator
**Location:** `app/services/bulkrax/csv_validation_service/validator.rb`

**Responsibility:** Core validation logic - check headers, required fields, and warnings

**Key Methods:**
- `missing_required_fields` - Returns array of missing required fields as `[{model:, field:}]`
- `unrecognized_headers` - Returns hash mapping unrecognized header names to spell-check suggestions
- `valid?` - Returns boolean (delegates to `!errors?`)
- `errors?` - Returns boolean (missing required fields, blank headers, or missing files)
- `warnings?` - Returns boolean (unrecognized headers or possible missing files)

**Details:** Normalizes headers by stripping numeric suffixes (`_1`, `_2`, etc.) so `creator_1` satisfies the `creator` requirement. Uses `DidYouMean::SpellChecker` for column name suggestions on unrecognized headers.

**Example:**
```ruby
validator = Validator.new(csv_headers, valid_headers, field_metadata, mapping_manager, file_validator)
validator.missing_required_fields  # => [{model: 'Work', field: 'title'}]
validator.unrecognized_headers     # => {'creatir' => 'creator', 'foo' => nil}
validator.valid?                   # => false
validator.errors?                  # => true
```

#### 16. FileValidator
**Location:** `app/services/bulkrax/csv_validation_service/file_validator.rb`

**Responsibility:** Validate file references against zip archive contents

**Key Methods:**
- `count_references` - Count total file references in CSV
- `missing_files` - Returns array of files referenced but not in zip
- `found_files_count` - Count files successfully found in zip
- `zip_included?` - Returns boolean indicating if zip was provided
- `possible_missing_files?` - Returns true if there are file references but no zip was uploaded

**Details:** Handles both `File` and `ActionDispatch::Http::UploadedFile` types. Compares basenames only (no path comparison). Accepts optional `admin_set_id` parameter.

**Example:**
```ruby
validator = FileValidator.new(csv_data, zip_file, admin_set_id)
validator.count_references       # => 10
validator.missing_files          # => ['image1.jpg', 'doc.pdf']
validator.found_files_count      # => 8
validator.possible_missing_files? # => false
```

#### 17. ItemExtractor
**Location:** `app/services/bulkrax/csv_validation_service/item_extractor.rb`

**Responsibility:** Extract and categorize items for UI display, with bidirectional parent-child relationship resolution

**Key Methods:**
- `collections` - Returns array of collection items with `parentIds` and `childIds`
- `works` - Returns array of work items with `parentIds` and `childIds` (excluding collections and file sets)
- `file_sets` - Returns array of file set items (without `parentIds` or `childIds`)
- `total_count` - Returns total number of items

**Bidirectional Relationship Resolution:**
The ItemExtractor automatically resolves parent-child relationships in both directions:
- If row A has `children: 'B|C'`, then B and C will have `parentIds` that include A
- Explicit parent values from the `parent` column are combined with inferred parents from `children` columns
- This ensures consistency regardless of which side of the relationship is specified in the CSV

**Model Categorization:** Uses `ModelLoader.determine_klass_for` to resolve model classes, then compares against `Bulkrax.collection_model_class` and `Bulkrax.file_model_class` to determine item type.

**Example:**
```ruby
extractor = ItemExtractor.new(csv_data)
extractor.collections  # => [{id: 'col1', title: 'My Collection', type: 'collection', parentIds: [], childIds: ['work1']}]
extractor.works        # => [{id: 'work1', title: 'My Work', type: 'work', parentIds: ['col1'], childIds: []}]
extractor.file_sets    # => [{id: 'fs1', title: 'File Set', type: 'file_set'}]
```

**CSV Example:**
```csv
source_identifier,children,parents
col1,work1|work2,
work1,,
work2,,
```
Result: `col1` has `childIds: ['work1', 'work2']`, and both `work1` and `work2` have `parentIds: ['col1']` (inferred from col1's children column)

#### 18. RowValidatorService
**Location:** `app/services/bulkrax/csv_validation_service/row_validator_service.rb`

**Responsibility:** Row-level validation via a configurable processor chain. Validates individual CSV rows for duplicate identifiers, broken parent references, missing required values, and invalid controlled vocabulary terms.

**Key Methods:**
- `self.default_processor_chain` (class attribute) - Ordered list of validation method symbols
- `validate` - Runs all chain methods, collects and returns an array of error hashes
- `each_row` (via `ValidatorHelpers`) - Iterates `csv_data` yielding `(row, row_number)` with correct 1-indexed row numbers

**Default Processor Chain:**
```ruby
Bulkrax::CsvValidationService::RowValidatorService.default_processor_chain
# => [:validate_duplicate_identifiers, :validate_parent_references, :validate_required_values, :validate_controlled_vocabulary]
```

**Sub-validator Classes (in `row_validator_service/` subdirectory):**

| File | Responsibility |
|------|----------------|
| `duplicate_identifier_validator.rb` | Detects `source_identifier` values that appear more than once |
| `invalid_relationship_validator.rb` | Detects `parent` references to `source_identifier` values not in the CSV |
| `required_values_validator.rb` | Detects blank values in required fields per model |
| `controlled_vocabulary_validator.rb` | Detects values not matching active QA vocabulary terms |
| `validator_helpers.rb` | `ValidatorHelpers` module providing the `each_row` iterator |

**Error Hash Structure:**
Each error returned by the chain follows this structure:

| Key | Type | Description |
|-----|------|-------------|
| `row` | Integer | 1-indexed row number |
| `source_identifier` | String | The record's source identifier |
| `severity` | String | `'error'` or `'warning'` |
| `category` | String | Machine-readable category (e.g. `'duplicate_source_identifier'`) |
| `column` | String | CSV column name affected |
| `value` | String | The cell value that triggered the issue |
| `message` | String | Human-readable description |
| `suggestion` | String\|nil | Actionable fix, or `nil` if not deterministic |

**Built-in Error Categories:**

| Category | Severity | Validator |
|----------|----------|-----------|
| `duplicate_source_identifier` | error | `DuplicateIdentifierValidator` |
| `invalid_parent_reference` | error | `InvalidRelationshipValidator` |
| `missing_required_value` | error | `RequiredValuesValidator` |
| `invalid_controlled_value` | error | `ControlledVocabularyValidator` |

**Configuration:** The active service class is configurable via `Bulkrax.config.row_validator_service`. See `STEPPER_IMPLEMENTATION.md` for details on extending or replacing the default chain.

## Field Mapping Resolution

The service uses Bulkrax's field mapping system to handle customizable column names:

```ruby
# Default mapping
'model' => { from: ['model'], split: false }

# Custom mapping (in Bulkrax config)
'model' => { from: ['work_type', 'object_type'], split: false }
```

The service automatically resolves these mappings through `MappingManager`:
- `mapped_to_key('work_type')` → `'model'`
- `key_to_mapped_column('model')` → `'work_type'`

## Error Handling

The service includes comprehensive error handling:

1. **Model Extraction:** Handles missing/invalid models gracefully (`ModelLoader` rescues `StandardError`)
2. **CSV Parsing:** Catches malformed CSV files (logged via `Rails.logger`)
3. **Zip Processing:** Handles missing/corrupted zip files (`FileValidator` rescues `StandardError`)
4. **Schema Analysis:** Fallback for models without schemas (`SchemaAnalyzer` returns `[]`)
5. **Valid Headers:** Falls back to combining standard fields + model properties if `ColumnBuilder` fails
6. **Rights Statement Override:** Special handling to treat missing `rights_statement` as warning instead of error when it's the only missing required field and there are no missing files

## Testing Strategy

The spec file (`csv_validation_service_spec.rb`, 317 lines) covers:

1. **Template Generation:** With and without Hyrax defined
2. **CSV Validation:** With and without zip files
3. **Missing Required Fields:** Detection and reporting
4. **Rights Statement Override:** Only when missing, no other missing required fields, no missing files
5. **Spell-Check Suggestions:** Misspelled header detection via `DidYouMean::SpellChecker`
6. **Hierarchical Item Extraction:** Collections, works, and file sets with relationship resolution
7. **File Validation:** References, found, and missing files
8. **Initialization:** Both generation and validation modes
9. **Field Metadata:** Retrieval for all models
10. **Valid Headers:** Generation and fallback behavior

## Usage in Controller

The controller concern `Bulkrax::GuidedImport` handles the web interface:
```ruby
# In GuidedImport controller concern (app/controllers/concerns/bulkrax/guided_import.rb)
def guided_import_validate
  files, error = resolve_validation_files
  return render json: error, status: :ok if error
  return render json: StepperResponseFormatter.error(message: 'No files uploaded'), status: :ok unless files.any?

  csv_file, zip_file = find_csv_and_zip(files)

  unless csv_file
    return render json: StepperResponseFormatter.error(message: 'No CSV metadata file uploaded'),
                  status: :ok unless zip_file
    csv_file, error = extract_csv_from_zip(zip_file)
    return render json: error, status: :ok if error
  end

  admin_set_id = params[:importer]&.[](:admin_set_id)
  render json: StepperResponseFormatter.format(
    run_validation(csv_file, zip_file, admin_set_id: admin_set_id)
  ), status: :ok
end
```

The controller:
- Resolves uploaded files (handling both direct uploads and file paths)
- Extracts CSV from zip if no separate CSV is provided
- Passes `admin_set_id` for context-gated schema resolution
- Formats results through `StepperResponseFormatter` for the stepper UI
- Supports a `DEMO_MODE` for testing without real validation

## Files

### Service Files
- `app/services/bulkrax/csv_validation_service.rb` - Main unified service
- `app/services/bulkrax/csv_validation_service/mapping_manager.rb` - Field mapping resolution
- `app/services/bulkrax/csv_validation_service/field_analyzer.rb` - Schema introspection
- `app/services/bulkrax/csv_validation_service/schema_analyzer.rb` - Property extraction
- `app/services/bulkrax/csv_validation_service/model_loader.rb` - Model loading
- `app/services/bulkrax/csv_validation_service/column_builder.rb` - Column assembly
- `app/services/bulkrax/csv_validation_service/column_descriptor.rb` - Core column definitions
- `app/services/bulkrax/csv_validation_service/csv_builder.rb` - CSV file generation
- `app/services/bulkrax/csv_validation_service/row_builder.rb` - Sample data rows
- `app/services/bulkrax/csv_validation_service/value_determiner.rb` - Sample cell values
- `app/services/bulkrax/csv_validation_service/explanation_builder.rb` - Field descriptions
- `app/services/bulkrax/csv_validation_service/split_formatter.rb` - Split pattern formatting
- `app/services/bulkrax/csv_validation_service/file_path_generator.rb` - Default file paths
- `app/services/bulkrax/csv_validation_service/csv_parser.rb` - CSV parsing
- `app/services/bulkrax/csv_validation_service/column_resolver.rb` - Column name resolution
- `app/services/bulkrax/csv_validation_service/validator.rb` - Core validation logic
- `app/services/bulkrax/csv_validation_service/file_validator.rb` - File/zip validation
- `app/services/bulkrax/csv_validation_service/item_extractor.rb` - Item categorization
- `app/services/bulkrax/csv_validation_service/row_validator_service.rb` - Row-level validation processor chain
- `app/services/bulkrax/csv_validation_service/row_validator_service/duplicate_identifier_validator.rb` - Duplicate source_identifier detection
- `app/services/bulkrax/csv_validation_service/row_validator_service/invalid_relationship_validator.rb` - Broken parent reference detection
- `app/services/bulkrax/csv_validation_service/row_validator_service/required_values_validator.rb` - Missing required value detection
- `app/services/bulkrax/csv_validation_service/row_validator_service/controlled_vocabulary_validator.rb` - Invalid controlled vocabulary detection
- `app/services/bulkrax/csv_validation_service/row_validator_service/validator_helpers.rb` - Shared `each_row` iterator module

### Related Files
- `app/controllers/concerns/bulkrax/guided_import.rb` - Controller concern using CsvValidationService
- `app/services/bulkrax/stepper_response_formatter.rb` - Formats validation results for the stepper UI
- `spec/services/bulkrax/csv_validation_service_spec.rb` - Comprehensive tests

## Future Enhancements

Potential additions to consider:

1. **Row-Level Validation:** Validate individual cell values
2. **Controlled Vocabulary Validation:** Check values against authorities
3. **Relationship Existence Validation:** Verify parent/child references exist in CSV (now that we extract childIds and parentIds, we could validate that referenced IDs actually exist)
4. **Circular Relationship Detection:** Detect and warn about circular parent-child relationships
5. **Type Coercion:** Suggest corrections for common data type errors
6. **Batch Processing:** Handle very large CSV files efficiently
7. **Incremental Validation:** Validate as user types in UI
8. **Detailed Error Messages:** Line numbers, suggested fixes
9. **Preview Generation:** Show how CSV will be imported with resolved relationships
