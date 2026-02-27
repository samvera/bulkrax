# Bulk Import Stepper - Implementation Guide

This document describes the guided import stepper wizard, a Rails-native multi-step import interface for Bulkrax.

## Overview

The stepper wizard is a 3-step process for bulk importing CSV files and associated media:

1. **Upload & Validate** - Upload CSV/ZIP files (or specify a server path), validate structure
2. **Configure Settings** - Set import name, visibility, rights statement, optional record limit
3. **Review & Start** - Review summary and confirm before starting the import

**Built with Bootstrap 4** - Uses native Bootstrap 4 components (cards, forms, buttons) with custom SCSS styling organized into 11 partials.

## Architecture

### Files

| Component | Path | Purpose |
|-----------|------|---------|
| Main View | `app/views/bulkrax/importers/guided_import_new.html.erb` | 3-step stepper form |
| JavaScript | `app/assets/javascripts/bulkrax/importers_stepper.js` | State management, validation, UI |
| JS Utilities | `app/assets/javascripts/bulkrax/bulkrax_utils.js` | HTML escaping, formatting helpers |
| Stylesheet | `app/assets/stylesheets/bulkrax/stepper.scss` | Main import file for 11 SCSS partials |
| Variables | `app/assets/stylesheets/bulkrax/stepper/_variables.scss` | Color palette and dimensions |
| Mixins | `app/assets/stylesheets/bulkrax/stepper/_mixins.scss` | Reusable SCSS mixins |
| Header | `app/assets/stylesheets/bulkrax/stepper/_header.scss` | Stepper progress header |
| Success | `app/assets/stylesheets/bulkrax/stepper/_success.scss` | Post-submission success card |
| Upload | `app/assets/stylesheets/bulkrax/stepper/_upload.scss` | Upload zone and file list |
| Validation | `app/assets/stylesheets/bulkrax/stepper/_validation.scss` | Accordion results styling |
| Summary | `app/assets/stylesheets/bulkrax/stepper/_summary.scss` | Import summary cards and tree |
| Settings | `app/assets/stylesheets/bulkrax/stepper/_settings.scss` | Settings form controls |
| Review | `app/assets/stylesheets/bulkrax/stepper/_review.scss` | Review step summary |
| Navigation | `app/assets/stylesheets/bulkrax/stepper/_navigation.scss` | Step navigation buttons |
| Responsive | `app/assets/stylesheets/bulkrax/stepper/_responsive.scss` | Mobile/tablet breakpoints |
| Controller | `app/controllers/concerns/bulkrax/guided_import.rb` | 4 endpoints + helpers |
| Formatter | `app/services/bulkrax/stepper_response_formatter.rb` | Validation response formatting |
| Helper | `app/helpers/bulkrax/importers_helper.rb` | Admin set enumeration |
| Row Validator | `app/services/bulkrax/csv_validation_service/row_validator_service.rb` | Row-level validation processor chain |

### Routes

Defined in `config/routes.rb` under the `importers` collection:

```ruby
get 'new/guided_import', action: :guided_import_new, as: :guided_import_new        # GET /importers/new/guided_import
post 'guided_import', action: :guided_import_create, as: :guided_import_create      # POST /importers/guided_import
post 'guided_import/validate', action: :guided_import_validate, as: :guided_import_validate  # POST /importers/guided_import/validate
get 'guided_import/demo_scenarios', action: :guided_import_demo_scenarios, as: :guided_import_demo_scenarios  # GET /importers/guided_import/demo_scenarios
```

## Step 1: Upload & Validate

### Upload Modes

The wizard supports two upload modes, toggled via tabs in the UI:

1. **Upload Files** - Drag-and-drop or browse for files (default)
2. **Import Path** - Specify a server-side directory path

### File Upload States

The JavaScript tracks 5 possible upload states:

| State | Constant | Description |
|-------|----------|-------------|
| Empty | `EMPTY` | No files uploaded |
| CSV Only | `CSV_ONLY` | Just a metadata CSV |
| ZIP Files Only | `ZIP_FILES_ONLY` | ZIP without separate CSV |
| ZIP with CSV | `ZIP_WITH_CSV` | ZIP that contains a CSV inside |
| CSV + ZIP | `CSV_AND_ZIP` | Separate CSV and ZIP files |

**Allowed file types:** `.csv` and `.zip` only (max 2 files).

### Admin Set Selection

Before validation, users must select an admin set. The admin set ID is:
- Passed to `CsvValidationService` for context-gated schema properties
- Used to update the CSV template download link
- Stored in the importer on creation

### CSV Template Download

A "Download a CSV template" link generates a template via `CsvValidationService.generate_template` for the selected admin set. The link URL updates dynamically when the admin set selection changes.

### Validation Flow

```
1. User uploads files or enters server path
2. User selects admin set
3. User clicks "Validate"
4. JavaScript builds FormData (or file path params) + admin_set_id
5. AJAX POST to /importers/guided_import/validate (60s timeout)
6. Controller resolves files -> finds CSV and ZIP -> extracts CSV from ZIP if needed
7. CsvValidationService.validate() processes CSV
8. StepperResponseFormatter.format() structures the response
9. JavaScript normalizes response (snake_case -> camelCase, relationship resolution)
10. JavaScript renders validation accordions, summary cards, hierarchy tree
11. If warnings present, user must acknowledge checkbox before proceeding
```

### Validation Results Display

Results are rendered as:

- **Validation Status Accordion** - Overall pass/fail with severity icon and details
- **Issue Accordions** - Missing required fields, unrecognized columns (with spell-check suggestions), file reference warnings
- **Import Summary** - Count cards for collections, works, and file sets
- **Hierarchy Tree** - Recursive tree view of collections -> works relationships (with circular reference detection, max depth of 50)
- **Import Size Gauge** - Visual indicator with three zones:
  - Green (0-100): Optimal size
  - Yellow (101-500): Moderate - consider splitting
  - Red (500+): Large - recommend batching

### ZIP CSV Extraction

When a ZIP is uploaded without a separate CSV, the controller attempts to extract a CSV from inside the ZIP:
- Groups ZIP entries by directory depth
- Prefers the shallowest (top-level) CSV
- Errors if no CSV found or if multiple CSVs exist at the same depth level

## Step 2: Configure Settings

The settings step collects:

- **Import Name** - Auto-generated with date, user-editable
- **Default Visibility** - Visual card selector with 3 options:
  - Public (open)
  - Institution (authenticated)
  - Private (restricted)
- **Optional Settings** (collapsed accordion):
  - Default Rights Statement dropdown
  - Override Rights Statement checkbox (force-apply to all records)
  - Test Limited Records input (import only N records for testing)

### Rights Statement UI Logic

The rights statement section dynamically shows/hides a "required" badge based on validation results. If the CSV is missing a `rights_statement` column and validation passed with warnings, the UI highlights that a default rights statement should be selected.

## Step 3: Review & Start

The review step displays:

- **Large Import Warning** - Alert for imports exceeding size thresholds
- **Files Summary** - File names and types being imported
- **Records Summary** - Counts of collections, works, and file sets
- **Settings Summary** - Chosen visibility, rights statement, record limit
- **Warnings Summary** - Any unresolved warnings from validation

## Controller Concern: `GuidedImport`

**Location:** `app/controllers/concerns/bulkrax/guided_import.rb`

### Public Actions

| Action | Method | Purpose |
|--------|--------|---------|
| `guided_import_new` | GET | Render the stepper form (with Hyrax breadcrumbs) |
| `guided_import_validate` | POST | AJAX validation endpoint |
| `guided_import_create` | POST | Create importer and start import job |
| `guided_import_demo_scenarios` | GET | Serve demo scenarios JSON from `lib/bulkrax/data/demo_scenarios.json` |

### `guided_import_validate` Details

1. Resolves files from either upload params or file path
2. Finds CSV and ZIP from the file list (by extension)
3. If no CSV found but ZIP exists, extracts CSV from the ZIP
4. Calls `CsvValidationService.validate(csv_file:, zip_file:, admin_set_id:)`
5. Formats result through `StepperResponseFormatter.format()`
6. Returns JSON response

### `guided_import_create` Details

1. Extracts uploaded files from params
2. Creates `Importer` with guided import strong parameters:
   - `name`, `admin_set_id`, `limit`
   - `parser_fields`: `visibility`, `rights_statement`, `override_rights_statement`, `import_file_path`, `file_style`
3. Sets `parser_klass` to `Bulkrax::CsvParser`
4. Associates with `current_user`
5. Applies field mapping from `Bulkrax.field_mappings["Bulkrax::CsvParser"]`
6. On save: writes files to disk via parser, enqueues `Bulkrax::ImporterJob`
7. Responds with redirect (HTML) or JSON

### Private Helpers

Key helpers include:

- `resolve_validation_files` - Returns `[files, error]` tuple from upload or file path
- `find_csv_and_zip(files)` - Scans files by extension, returns `[csv_file, zip_file]`
- `extract_csv_from_zip(zip_file)` - Opens ZIP, finds CSV, returns `[csv_file, error]`
- `find_csv_in_zip(zip)` - Smart CSV discovery preferring shallowest directory level
- `run_validation(csv_file, zip_file, admin_set_id:)` - Delegates to `CsvValidationService` or demo mode
- `write_guided_import_files(files)` - Writes CSV and ZIP to disk via parser methods
- `generate_validation_response` - Mock data generator for demo mode
- `build_validation_messages` - Format validation response structure
- `validation_status` / `validation_status_level` - Determine severity, icon, and title
- `missing_required_issue` / `unrecognized_fields_issue` / `file_references_issue` - Format individual issues
- `import_via_file_path?` / `import_file_path` - File path mode helpers

## StepperResponseFormatter

**Location:** `app/services/bulkrax/stepper_response_formatter.rb`

Transforms raw `CsvValidationService` output into a structured response for the frontend.

### Public API

```ruby
# Format validation data for the stepper UI
StepperResponseFormatter.format(validation_data)

# Generate an error response
StepperResponseFormatter.error(message: 'Something went wrong', summary: 'Error details')
```

### Output Structure

```ruby
{
  # Pass-through from CsvValidationService
  headers: [...],
  missingRequired: [...],
  unrecognized: {...},
  rowCount: 247,
  isValid: true,
  hasWarnings: false,
  collections: [...],
  works: [...],
  fileSets: [...],
  totalItems: 247,
  fileReferences: 55,
  missingFiles: [...],
  foundFiles: 52,
  zipIncluded: true,

  # Added by formatter
  messages: {
    validationStatus: {
      severity: 'success',        # 'success', 'warning', or 'error'
      icon: 'fa-check-circle',    # FontAwesome icon class
      title: 'Validation Passed',
      summary: '15 columns detected across 247 records',
      details: 'Recognized fields: title, creator, ...',
      defaultOpen: true
    },
    issues: [
      {
        type: 'missing_required',
        severity: 'error',         # or 'warning' for rights_statement only
        icon: 'fa-times-circle',
        title: 'Missing Required Fields',
        count: 2,
        description: '...',
        items: ['title (Work)', 'creator (Work)'],
        defaultOpen: true
      },
      # ... unrecognized_fields, file_references issues
    ]
  }
}
```

### Special Cases

- **Rights statement only missing:** Severity is `warning` instead of `error`, with helpful context about setting a default in Step 2
- **Unrecognized fields:** Items include "Did you mean X?" suggestions from the spell checker
- **File references:** Different messaging for "missing files in ZIP" vs "no ZIP uploaded"

## JavaScript Architecture

**Location:** `app/assets/javascripts/bulkrax/importers_stepper.js`

### Dependencies

- jQuery (global)
- `BulkraxUtils` from `bulkrax_utils.js` (provides `escapeHtml`, `formatFileSize`, `normalizeBoolean`)

### State Management

All wizard state lives in a `StepperState` object:

```javascript
var StepperState = {
  currentStep: 1,
  uploadedFiles: [],
  uploadState: 'empty',           // One of UPLOAD_STATES constants
  uploadMode: 'upload',           // 'upload' or 'file_path'
  validated: false,
  validationData: null,
  warningsAcked: false,
  skipValidation: false,
  isAddingFiles: false,
  demoScenario: null,
  demoScenariosData: null,        // Cached demo scenarios JSON
  uploadsInProgress: 0,
  adminSetId: '',
  adminSetName: '',
  settings: {
    name: '',
    visibility: 'open',
    rightsStatement: '',
    limit: ''
  }
}
```

### Constants

```javascript
MAX_FILES: 2
IMPORT_SIZE_OPTIMAL: 100
IMPORT_SIZE_MODERATE: 500
IMPORT_SIZE_LARGE: 1000
ALLOWED_EXTENSIONS: ['.csv', '.zip']
ANIMATION_SPEED: 200           // ms
SCROLL_SPEED: 300              // ms
VALIDATION_DELAY: 2000         // ms
NOTIFICATION_FADE_SPEED: 300   // ms
DEBOUNCE_DELAY: 300            // ms
AJAX_TIMEOUT_SHORT: 10000      // 10s for simple requests
AJAX_TIMEOUT_LONG: 120000      // 2min for file uploads/validation
CHUNK_SIZE: 10000000           // 10 MB per upload chunk
MAX_TREE_DEPTH: 50             // Prevent stack overflow
```

### Key Function Groups

**Initialization:**
- `initBulkImportStepper()` - Main entry point, binds events
- `bindEvents()` / `bindDelegatedEvents()` - Event handlers with Turbolinks guard

**File Handling:**
- `handleFileSelect(isAddingMore)` - Process uploaded files with type validation
- `renderUploadedFiles()` - Display file list with icons and status badges
- `renderFileRow(type, name, subtitle, validationStatus)` - Individual file row
- `switchUploadMode(mode)` - Toggle upload vs file path modes
- `updateUploadState()` - Calculate state from current files
- `resetUploadState()` / `startOver()` - Clear and reset

**Validation:**
- `validateFiles()` - Orchestrate validation based on upload mode
- `performValidation(formData)` - AJAX POST to validate endpoint
- `performFilePathValidation(filePath)` - Validate server path mode
- `handleValidationSuccess(data, $btn)` / `handleValidationError(error, $btn)` - Response handlers
- `normalizeValidationData(data)` - Snake_case to camelCase conversion
- `normalizeRelationships(data)` - Convert childrenIds to parentIds hierarchy

**Rendering:**
- `renderValidationResults(data)` - Main rendering orchestrator
- `renderImportSizeGauge(count)` - Visual gauge with three color zones
- `renderValidationAccordions(data)` - Status and issue accordions
- `renderImportSummary(data, hierarchyMap)` - Summary cards and tree
- `renderTreeItem(item, hierarchyMap, depth, visited)` - Recursive tree with circular reference detection

**Navigation:**
- `goToStep(stepNum)` - Navigate to step
- `updateStepperUI()` - Update header, connectors, content visibility
- `updateStepNavigation()` - Enable/disable buttons based on state
- `updateReviewSummary()` - Populate Step 3 review content
- `updateStep2RightsStatementUI()` - Dynamic rights statement badge

**Settings:**
- `initVisibilityCards()` - Card selection UI
- `setDefaultImportName()` - Auto-generate name with date
- `updateDownloadTemplateLink()` - Update template URL with admin set ID

**Form Submission:**
- `handleImportSubmit()` - Prepare and submit form to `guided_import_create`
- `syncFilesToInput()` - Sync state files to hidden form input

**Demo Mode:**
- `loadDemoScenariosData()` - Fetch JSON from `/importers/guided_import/demo_scenarios`
- `loadDemoScenario(scenario)` - Load mock files and validation data
- `getMockValidationData()` - Look up mock data for current scenario

## Utility JavaScript

**Location:** `app/assets/javascripts/bulkrax/bulkrax_utils.js`

Provides `window.BulkraxUtils` with:

- `escapeHtml(unsafe)` - XSS prevention via HTML entity encoding
- `formatFileSize(bytes)` - Convert bytes to human-readable format (KB, MB, GB)
- `normalizeBoolean(value)` - Convert string/boolean to `true`/`false`/`null`

## Styling

### SCSS Variables (`stepper/_variables.scss`)

```scss
// Brand colors
$color-primary: #2b6da5;
$color-success: #5cb85c;
$color-success-bright: #28a745;
$color-warning: #ffc107;
$color-error: #dc3545;
$color-info: #17a2b8;

// Text colors
$color-text-dark: #333;
$color-text-muted: #6c757d;
$color-text-disabled: #adb5bd;
$color-text-default: #495057;

// Severity backgrounds
$bg-success: #d7e5d7;
$bg-warning: #fff3cd;
$bg-error: #f8d7da;
$bg-info: #d1ecf1;

// Severity borders
$border-success: #c3e6cb;
$border-warning: #ffeaa7;
$border-error: #f5c6cb;
$border-info: #b8daff;

// Layout
$border-radius: 8px;
```

### Components Styled

| Partial | Styles |
|---------|--------|
| `_header` | Step circles (50px), labels, connectors with animated transitions |
| `_success` | Post-submission success card |
| `_upload` | Dropzone, file list with icons/badges, file path input |
| `_validation` | Collapsible accordions with severity color coding |
| `_summary` | Count cards, hierarchy tree view |
| `_settings` | Visibility card selector, form controls |
| `_review` | Summary sections for final review |
| `_navigation` | Back/Next/Submit buttons per step |
| `_responsive` | Mobile/tablet breakpoints |

## View Structure

**Location:** `app/views/bulkrax/importers/guided_import_new.html.erb`

The view wraps everything in a single `form_for [:bulkrax, Bulkrax::Importer.new]` (multipart, posting to `guided_import_create_importers_path`):

- **Stepper Header** - 3-step progress indicator with icons (cloud-upload, cog, play)
- **Success State** - Hidden card shown after successful submission
- **Step 1: Upload & Validate**
  - Upload mode tabs (Upload Files / Import Path)
  - Drag-and-drop dropzone
  - Demo scenarios panel (hidden by default)
  - Uploaded files container
  - "Add another" secondary dropzone
  - File path input panel
  - Admin set dropdown (required)
  - Download template link
  - Validate buttons (one per upload mode)
  - Validation results area (accordions + summary)
  - Warning acknowledgment checkbox
  - Navigation: Clear & Start Over, Next
- **Step 2: Configure Settings**
  - Import name input
  - Visibility card selector (Public / Institution / Private)
  - Optional settings accordion (rights statement, override checkbox, record limit)
  - Navigation: Back, Next
- **Step 3: Review & Start**
  - Large import warning alert
  - Review summary (files, records, settings, warnings)
  - Navigation: Back, Start Import
- **Hidden State Container** - Data attributes for persisting stepper state (`data-current-step`, `data-validated`, `data-has-warnings`, `data-warnings-acked`, `data-upload-state`, `data-validation-data`)

## Helper

**Location:** `app/helpers/bulkrax/importers_helper.rb` (14 lines)

- `available_admin_sets` - Returns `[title, id]` tuples for admin sets the current user can deposit to, using `Hyrax::Collections::PermissionsService`.

## Data Flows

### Validation Request Flow

```
Browser                     Controller                  Services
  |                            |                           |
  |-- POST /guided_import/ --->|                           |
  |   validate                 |                           |
  |  (FormData + admin_set_id) |                           |
  |                            |-- resolve_validation_files|
  |                            |-- find_csv_and_zip        |
  |                            |-- extract_csv_from_zip?   |
  |                            |                           |
  |                            |-- CsvValidationService -->|
  |                            |  .validate(csv, zip, id)  |
  |                            |                           |
  |                            |<-- validation result -----|
  |                            |                           |
  |                            |-- StepperResponseFormatter|
  |                            |  .format(result)          |
  |                            |                           |
  |<-- JSON response ----------|                           |
  |                            |                           |
  |-- normalizeValidationData  |                           |
  |-- normalizeRelationships   |                           |
  |-- renderValidationResults  |                           |
```

### Import Creation Flow

```
Browser                     Controller                  Background
  |                            |                           |
  |-- POST /guided_import ---->|                           |
  |  (form with files)         |                           |
  |                            |-- Importer.new(params)    |
  |                            |-- importer.save           |
  |                            |-- write_guided_import_    |
  |                            |   files(files)            |
  |                            |                           |
  |                            |-- ImporterJob ------------->|
  |                            |  .perform_later            |  |
  |                            |                           |  |
  |<-- redirect to importers --|                     (async import)
```

## Demo Mode

The stepper includes a demo mode for testing without real files:

1. Double-click the upload zone to reveal the demo scenarios panel
2. Demo scenarios are fetched from `GET /importers/guided_import/demo_scenarios` (reads `lib/bulkrax/data/demo_scenarios.json`)
3. Select a scenario to load mock files and validation data
4. Validation uses mock data from the controller's `generate_validation_response` method
5. All UI features (accordions, tree, gauge, navigation) are testable without real backend processing

## Testing

### Demo Mode Testing

1. Double-click the upload zone to show demo scenario buttons
2. Select a scenario to load mock data
3. Click Validate to see mock validation results
4. Navigate through all 3 steps

### Real File Testing

1. Upload actual CSV and/or ZIP files
2. Select an admin set
3. Click Validate to call the real backend endpoint
4. Form submission creates a real `Importer` and enqueues `ImporterJob`

### Spec File

**Location:** `spec/controllers/concerns/bulkrax/guided_import_spec.rb`

## Usage

### For Users

1. Navigate to Importers index
2. Click "Guided Import" button
3. Follow the 3-step wizard:
   - Upload files (or enter server path), select admin set, and validate
   - Configure import name, visibility, and optional settings
   - Review summary and start import
4. Monitor progress in the import queue

### For Developers

#### Customizing Validation

Validation logic lives in `CsvValidationService` and its subclasses (see `docs/CSV_SERVICE_ARCHITECTURE.md`). The controller delegates to the service and formats results through `StepperResponseFormatter`.

#### Extending Row Validation

Row validation is powered by `CsvValidationService::RowValidatorService`, which uses a processor chain that runs four validators in order:

```ruby
Bulkrax::CsvValidationService::RowValidatorService.default_processor_chain
# => [:validate_duplicate_identifiers, :validate_parent_references, :validate_required_values, :validate_controlled_vocabulary]
```

Each method in the chain receives a shared `errors` array and appends to it directly. All errors are collected and returned together.

##### Registering a Custom Validator Service

Tell Bulkrax to use your subclass via the initializer:

```ruby
# config/initializers/bulkrax.rb
Bulkrax.config do |config|
  config.row_validator_service = MyRowValidatorService
end
```

##### Adding a Custom Validator

Subclass `RowValidatorService` and append your method to the chain. Each method receives an `errors` array — append error hashes to it directly:

```ruby
class MyRowValidatorService < Bulkrax::CsvValidationService::RowValidatorService
  self.default_processor_chain += [:validate_duplicate_titles]

  def validate_duplicate_titles(errors)
    seen = {}

    each_row do |row, row_number|
      title = row[:raw_row]['title']
      next if title.blank?

      if seen[title]
        errors << {
          row: row_number,
          source_identifier: row[:source_identifier],
          severity: 'error',
          category: 'duplicate_title',
          column: 'title',
          value: title,
          message: "Duplicate title '#{title}' — also appears in row #{seen[title]}.",
          suggestion: 'Each record should have a unique title.'
        }
      else
        seen[title] = row_number
      end
    end
  end
end
```

`each_row` is provided by `RowValidatorService` and yields each row along with the correct 1-indexed row number (accounting for the header row).

For more complex validators, extract the logic into a dedicated class. The dedicated class should include `ValidatorHelpers` to get access to `each_row`:

```ruby
class DuplicateTitleValidator
  include Bulkrax::CsvValidationService::RowValidatorService::ValidatorHelpers

  def initialize(csv_data, field_metadata, manager_mapper)
    @csv_data = csv_data
    @field_metadata = field_metadata
    @manager_mapper = manager_mapper
  end

  def validate(errors)
    seen = {}

    each_row do |row, row_number|
      # ... validation logic appending to errors
    end
  end
end

class MyRowValidatorService < Bulkrax::CsvValidationService::RowValidatorService
  self.default_processor_chain += [:validate_duplicate_titles]

  def validate_duplicate_titles(errors)
    DuplicateTitleValidator.new(csv_data, field_metadata, manager_mapper).validate(errors)
  end
end
```

##### Overriding a Built-in Validator

To skip or replace a built-in validator, override its method:

```ruby
class MyRowValidatorService < Bulkrax::CsvValidationService::RowValidatorService
  # Skip duplicate identifier checking entirely
  def validate_duplicate_identifiers(errors)
    # no-op
  end

  # Replace with custom implementation
  def validate_controlled_vocabulary(errors)
    each_row do |row, row_number|
      # custom logic appending to errors
    end
  end
end
```

##### Available Data in Chain Methods

All chain methods have access to these readers inherited from `RowValidatorService`:

| Reader | Type | Description |
|--------|------|-------------|
| `csv_data` | `Array<Hash>` | Parsed CSV rows with `:source_identifier`, `:model`, `:parent`, `:children`, `:raw_row` |
| `field_metadata` | `Hash` | Model field metadata including `required_terms` and `controlled_vocab_terms` |
| `manager_mapper` | `CsvValidationService::MappingManager` | Bulkrax field mapping resolver |
| `each_row` | `method` | Iterates `csv_data` yielding `(row, row_number)` with correct 1-indexed row numbers |

##### Error Hash Structure

Each error appended to the `errors` array must follow this structure:

| Key | Type | Description |
|-----|------|-------------|
| `row` | Integer | 1-indexed row number (use `row_number` from `each_row`) |
| `source_identifier` | String | The record's source identifier |
| `severity` | String | `'error'` or `'warning'` |
| `category` | String | Machine-readable category (e.g. `'duplicate_title'`) |
| `column` | String | CSV column name affected |
| `value` | String | The cell value that triggered the issue |
| `message` | String | Human-readable description |
| `suggestion` | String | Actionable fix, or `nil` if not deterministic |

##### Built-in Validator Categories

| Category | Severity | Description |
|----------|----------|-------------|
| `duplicate_source_identifier` | error | `source_identifier` appears more than once in the CSV |
| `invalid_parent_reference` | error | `parent` references a `source_identifier` not found in the CSV |
| `missing_required_value` | error | A required field is blank for a specific row |
| `invalid_controlled_value` | error | Value does not match any active term in the configured QA vocabulary |

#### Adding New Steps

1. Add step HTML to `guided_import_new.html.erb` (follow existing step pattern)
2. Update stepper header with new step circle and connector
3. Add navigation logic in `goToStep()` and `updateStepperUI()` in the JavaScript
4. Update `updateStepNavigation()` for enable/disable logic

#### Styling Customization

All SCSS variables are in `stepper/_variables.scss`. Override colors:

```scss
$color-primary: #337ab7;
$color-success: #5cb85c;
$color-warning: #ffc107;
$color-error: #dc3545;
```

Gauge segment colors are derived from the severity border variables:
```scss
$border-success: #c3e6cb;  // Optimal zone
$border-warning: #ffeaa7;  // Moderate zone
$border-error: #f5c6cb;    // Large zone
```

#### Response Formatting

To customize how validation results are presented, modify `StepperResponseFormatter`. It transforms raw `CsvValidationService` output into the `messages` structure consumed by the JavaScript rendering functions.

## Troubleshooting

### Assets Not Loading

```bash
rake assets:precompile
```

### JavaScript Not Working

- Check browser console for errors
- Verify jQuery is loaded before `importers_stepper.js`
- Verify `bulkrax_utils.js` loads before `importers_stepper.js`
- Check Turbolinks compatibility (events use a guard flag to prevent double-binding)

### Validation Fails

- Check server logs for backend errors
- Verify file upload size limits in your web server config
- Ensure `CsvValidationService` can load the models referenced in the CSV
- Check that the admin set exists and user has deposit permissions

### Styling Issues

- Clear browser cache
- Check for CSS conflicts with existing application styles
- Verify Bootstrap 4 is loaded
- SCSS partials are imported in order - check `stepper.scss` for import sequence

## Migration from Old Form

The old importer form is still available at `/importers/new`. To fully migrate:

1. Test the guided import thoroughly with various file types and edge cases
2. Train users on the new interface
3. Consider deprecating the old form
4. Update documentation and help text

## Future Enhancements

Potential improvements:

1. Real-time progress updates during validation
2. Drag-and-drop file reordering
3. Inline CSV editor for quick fixes
4. Save draft imports for later
5. Enhanced error messages with line numbers and suggested fixes
6. File preview before import
7. Duplicate detection
8. Capybara/Selenium integration tests for the stepper UI
