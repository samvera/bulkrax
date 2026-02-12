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
CsvValidationService.generate_template(models: 'all', output: 'file')
```

**Purpose:** Create sample CSV templates showing valid structure and fields

**Key Components Used:**
- `ModelLoader` - Loads specified models or all available models
- `FieldAnalyzer` - Extracts schema information from models
- `ColumnBuilder` - Assembles valid column names
- `CsvBuilder` - Generates CSV content
- `RowBuilder` - Creates sample data rows
- `ExplanationBuilder` - Adds helpful descriptions

#### 2. Validation Mode
```ruby
service = CsvValidationService.new(csv_file: csv_file, zip_file: zip_file)
# OR
CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file)
```

**Purpose:** Validate uploaded CSV files against model schemas

**Key Components Used (Specialized Subclasses):**
- `CsvParser` - Parses CSV files, extracts headers and structured data
- `ColumnResolver` - Resolves CSV column names from Bulkrax field mappings
- `Validator` - Validates headers, checks required fields, identifies unrecognized columns
- `FileValidator` - Validates file references against zip archive
- `ItemExtractor` - Extracts and categorizes collections, works, and file sets
- `FieldAnalyzer` - Gets required fields, controlled vocab, etc. (shared)
- `ColumnBuilder` - Determines valid headers (shared)

## Component Reuse

With this architecture, both modes share the same underlying components:

```
┌──────────────────────────────────────────────────────────┐
│                CsvValidationService                      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │       Common Components (Both Modes)               │ │
│  │                                                    │ │
│  │  • MappingManager    - Field mapping resolution   │ │
│  │  • FieldAnalyzer     - Schema introspection       │ │
│  │  • ModelLoader       - Model loading/validation   │ │
│  │  • ColumnBuilder     - Valid column assembly      │ │
│  │  • SchemaAnalyzer    - Property extraction        │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────────┐ │
│  │  Generation Mode     │  │   Validation Mode        │ │
│  │                      │  │                          │ │
│  │  • CsvBuilder        │  │  • CsvParser             │ │
│  │  • RowBuilder        │  │  • ColumnResolver        │ │
│  │  • ExplanationBuilder│  │  • Validator             │ │
│  │  • FilePathGenerator │  │  • FileValidator         │ │
│  │                      │  │  • ItemExtractor         │ │
│  └──────────────────────┘  └──────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

## Key Methods

### Public API

#### Template Generation
```ruby
# Class method
CsvValidationService.generate_template(models: ['Work'], output: 'file')

# Instance methods
service = CsvValidationService.new(models: ['Work'])
service.to_file(file_path: 'path/to/file.csv')
service.to_csv_string
```

#### Validation
```ruby
# Class method
result = CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file)

# Returns:
{
  headers: [...],              # Column names in CSV
  missingRequired: [...],      # Missing required fields
  unrecognized: [...],         # Unrecognized columns
  rowCount: 247,               # Total rows
  isValid: true/false,         # Overall validity
  hasWarnings: true/false,     # Has warnings
  collections: [...],          # Collection items
  works: [...],                # Work items
  fileSets: [...],             # File set items
  allItems: [...],             # Collections + works
  totalItems: 247,             # Total count
  fileReferences: 55,          # File refs in CSV
  missingFiles: [...],         # Files not in zip
  foundFiles: 52,              # Files in zip
  zipIncluded: true/false      # Zip provided
}
```

### Shared Analysis Methods

```ruby
service = CsvValidationService.new(models: ['Work'])

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
1. Initialize with models
2. ModelLoader loads model classes
3. FieldAnalyzer extracts schema for each model
4. ColumnBuilder assembles valid columns
5. RowBuilder creates sample rows
6. CsvBuilder writes to file/string
```

### Validation Mode Flow
```
1. Initialize with csv_file (+ optional zip_file)
2. Create ColumnResolver with field mappings
3. Create CsvParser → parses CSV, extracts headers and data
4. CsvParser extracts unique models from CSV
5. Create FileValidator → analyzes zip contents
6. Create ItemExtractor → categorizes CSV rows
7. ModelLoader validates models exist
8. FieldAnalyzer gets schema for found models
9. Create Validator → compares headers, checks required fields
10. Return comprehensive validation results
```

## Validation Subclasses

The validation mode delegates to 5 specialized subclasses, each with a focused responsibility:

### 1. CsvParser
**Location:** `app/services/bulkrax/csv_validation_service/csv_parser.rb`

**Responsibility:** Parse CSV files and extract structured data

**Key Methods:**
- `headers` - Returns array of CSV column names
- `extract_models` - Extracts unique model names from CSV
- `parse_data` - Parses CSV into structured hashes for validation

**Example:**
```ruby
parser = CsvParser.new(csv_file, column_resolver)
parser.headers          # => ['model', 'title', 'creator']
parser.extract_models   # => ['GenericWork', 'Collection']
parser.parse_data       # => [{source_identifier: 'work1', model: 'GenericWork', ...}]
```

### 2. ColumnResolver
**Location:** `app/services/bulkrax/csv_validation_service/column_resolver.rb`

**Responsibility:** Resolve CSV column names from Bulkrax field mappings

**Key Methods:**
- `model_column_name(csv_headers)` - Finds the column used for model/work type
- `source_identifier_column_name(csv_headers)` - Finds the source identifier column
- `parent_column_name(csv_headers)` - Finds the parent relationships column
- `file_column_name(csv_headers)` - Finds the file reference column

**Why It's Needed:** Bulkrax allows custom field mappings, so the CSV might use `work_type` instead of `model`, or `id` instead of `source_identifier`. This class handles those variations.

**Example:**
```ruby
resolver = ColumnResolver.new(mappings)
resolver.model_column_name(['work_type', 'title'])      # => 'work_type'
resolver.source_identifier_column_name(['id', 'title']) # => 'id'
```

### 3. Validator
**Location:** `app/services/bulkrax/csv_validation_service/validator.rb`

**Responsibility:** Core validation logic - check headers, required fields, and warnings

**Key Methods:**
- `missing_required_fields` - Returns array of missing required fields
- `unrecognized_headers` - Returns array of unrecognized column names
- `valid?` - Returns boolean indicating if CSV is valid
- `warnings?` - Returns boolean indicating if there are warnings

**Example:**
```ruby
validator = Validator.new(csv_headers, valid_headers, field_metadata, mapping_manager)
validator.missing_required_fields  # => [{model: 'Work', field: 'title'}]
validator.unrecognized_headers     # => ['invalid_column']
validator.valid?                   # => false
```

### 4. FileValidator
**Location:** `app/services/bulkrax/csv_validation_service/file_validator.rb`

**Responsibility:** Validate file references against zip archive contents

**Key Methods:**
- `count_references` - Count total file references in CSV
- `missing_files` - Returns array of files referenced but not in zip
- `found_files_count` - Count files successfully found in zip
- `zip_included?` - Returns boolean indicating if zip was provided

**Example:**
```ruby
validator = FileValidator.new(csv_data, zip_file)
validator.count_references       # => 10
validator.missing_files          # => ['image1.jpg', 'doc.pdf']
validator.found_files_count      # => 8
```

### 5. ItemExtractor
**Location:** `app/services/bulkrax/csv_validation_service/item_extractor.rb`

**Responsibility:** Extract and categorize items for UI display

**Key Methods:**
- `collections` - Returns array of collection items
- `works` - Returns array of work items (excluding collections and file sets)
- `file_sets` - Returns array of file set items
- `all_items` - Returns combined collections and works
- `total_count` - Returns total number of items

**Example:**
```ruby
extractor = ItemExtractor.new(csv_data)
extractor.collections  # => [{id: 'col1', title: 'My Collection', type: 'collection'}]
extractor.works        # => [{id: 'work1', title: 'My Work', type: 'work'}]
```

## Field Mapping Resolution

The service uses Bulkrax's field mapping system to handle customizable column names:

```ruby
# Default mapping
'model' => { from: ['model'], split: false }

# Custom mapping (in Bulkrax config)
'model' => { from: ['work_type', 'object_type'], split: false }
```

The service automatically resolves these mappings through `MappingManager`:
- `mapped_to_key('work_type')` → 'model'
- `key_to_mapped_column('model')` → 'work_type'

## Error Handling

The service includes comprehensive error handling:

1. **Model Extraction:** Handles missing/invalid models gracefully
2. **CSV Parsing:** Catches malformed CSV files
3. **Zip Processing:** Handles missing/corrupted zip files
4. **Schema Analysis:** Fallback for models without schemas
5. **File Operations:** Proper cleanup and error messages

## Testing Strategy

The spec file (`csv_service_spec.rb`) covers:

1. **Class Methods:** Both `generate_template` and `validate`
2. **Initialization:** Both generation and validation modes
3. **Shared Methods:** Field metadata, valid headers
4. **Validation Logic:**
   - Header extraction
   - Required field detection
   - Unrecognized column identification
   - File reference validation
   - Item categorization (collections, works, file sets)
5. **Private Methods:** CSV parsing, model extraction, file handling

## Future Enhancements

Potential additions to consider:

1. **Row-Level Validation:** Validate individual cell values
2. **Controlled Vocabulary Validation:** Check values against authorities
3. **Relationship Validation:** Verify parent/child references exist
4. **Type Coercion:** Suggest corrections for common data type errors
5. **Batch Processing:** Handle very large CSV files efficiently
6. **Incremental Validation:** Validate as user types in UI
7. **Detailed Error Messages:** Line numbers, suggested fixes
8. **Preview Generation:** Show how CSV will be imported

## Benefits of This Architecture

✅ **No Duplication:** All schema analysis logic in one place
✅ **Single Source of Truth:** Field definitions defined once
✅ **Shared Components:** Common components used by both modes
✅ **Natural Dependencies:** Validation uses same logic as generation
✅ **Modular Design:** 5 focused subclasses, each ~70-100 lines
✅ **Single Responsibility:** Each subclass has one clear purpose
✅ **Testable:** Clear boundaries, easy to mock and test
✅ **Reusable:** Subclasses can be used independently
✅ **Maintainable:** Small classes are easier to understand and modify
✅ **Extensible:** Easy to add new validation rules or extractors
✅ **Clean Orchestration:** Main service is ~250 lines, well-organized

## Usage in Controller

```ruby
# In ImporterV2 controller concern
def validate_v2
  csv_file = params[:importer][:parser_fields][:files].find { |f| f.original_filename&.end_with?('.csv') }
  zip_file = params[:importer][:parser_fields][:files].find { |f| f.original_filename&.end_with?('.zip') }

  response = Bulkrax::CsvValidationService.validate(csv_file, zip_file)
  render json: response, status: :ok
end
```

## Files Changed

### New Files
- `app/services/bulkrax/csv_validation_service.rb` - Main unified service (~120 lines, down from ~500)
- `app/services/bulkrax/csv_validation_service/csv_parser.rb` - CSV parsing (~100 lines)
- `app/services/bulkrax/csv_validation_service/column_resolver.rb` - Column name resolution (~90 lines)
- `app/services/bulkrax/csv_validation_service/validator.rb` - Core validation logic (~70 lines)
- `app/services/bulkrax/csv_validation_service/file_validator.rb` - File/zip validation (~95 lines)
- `app/services/bulkrax/csv_validation_service/item_extractor.rb` - Item categorization (~80 lines)
- `spec/services/bulkrax/csv_validation_service_spec.rb` - Comprehensive tests
- `CSV_SERVICE_ARCHITECTURE.md` - This documentation

### Modified Files
- `app/controllers/concerns/bulkrax/importer_v2.rb` - Uses CsvValidationService for validation

## Component Integration

The service integrates with existing Bulkrax components from `sample_csv_service/`:

- `MappingManager` - Field mapping resolution
- `FieldAnalyzer` - Schema introspection
- `ModelLoader` - Model loading and validation
- `ColumnBuilder` - Valid column assembly
- `SchemaAnalyzer` - Property extraction
- `CsvBuilder` - CSV file generation (generation mode)
- `RowBuilder` - Sample data creation (generation mode)
- `ExplanationBuilder` - Field descriptions (generation mode)

These components are shared infrastructure that work with both template generation and validation modes.
