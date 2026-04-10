# Bulkrax Import Metrics - Query Reference

## Table Schema

All metrics are stored in `bulkrax_import_metrics`:

| Column | Type | Description |
|---|---|---|
| `id` | integer | Primary key |
| `metric_type` | string | One of: `funnel`, `validation`, `import_outcome`, `feedback`, `timing` |
| `event` | string | Specific event name within the metric type |
| `importer_id` | integer | FK to `bulkrax_importers` (null for client-side metrics) |
| `user_id` | integer | FK to `users` (null for unauthenticated beacon calls) |
| `session_id` | string | Links all metrics from one guided import session (e.g. `gi_a1b2c3d4e`) |
| `payload` | jsonb | Event-specific data (varies by metric type) |
| `created_at` | timestamp | When the metric was recorded |

## Model Scopes

```ruby
Bulkrax::ImportMetric.funnel          # metric_type = 'funnel'
Bulkrax::ImportMetric.validations     # metric_type = 'validation'
Bulkrax::ImportMetric.import_outcomes # metric_type = 'import_outcome'
Bulkrax::ImportMetric.feedback        # metric_type = 'feedback'
Bulkrax::ImportMetric.timing          # metric_type = 'timing'
Bulkrax::ImportMetric.in_range(from, to) # created_at between from..to
```

---

## Metric Types and Their Payloads

### 1. Funnel (`metric_type = 'funnel'`)

Tracks which steps a user reaches in the guided import wizard.

**Event:** `step_reached`

| Payload Key | Type | Values |
|---|---|---|
| `step` | integer or string | `1`, `2`, `3`, or `"submitted"` |

**Example queries:**

```ruby
# Step completion counts (how many sessions reached each step)
ImportMetric.funnel.in_range(from, to)
  .group("(payload->>'step')::integer")
  .count
# => {1 => 150, 2 => 120, 3 => 95}

# Drop-off between steps
funnel = ImportMetric.funnel.in_range(30.days.ago, Time.current)
step1 = funnel.where("payload->>'step' = '1'").count
step3 = funnel.where("payload->>'step' = '3'").count
drop_off_rate = ((step1 - step3).to_f / step1 * 100).round(1)

# Sessions that reached submit
ImportMetric.funnel.in_range(from, to)
  .where("payload->>'step' = ?", 'submitted')
  .count
```

---

### 2. Validation (`metric_type = 'validation'`)

Recorded server-side when a CSV validation completes.

**Event:** `validation_complete`

| Payload Key | Type | Description |
|---|---|---|
| `outcome` | string | `"pass"`, `"pass_with_warnings"`, or `"fail"` |
| `row_count` | integer | Number of rows in the CSV |
| `duration_ms` | integer | How long validation took |
| `missing_required_count` | integer | Count of missing required headers |
| `unrecognized_count` | integer | Count of unrecognized headers |
| `empty_columns_count` | integer | Count of empty column positions |
| `row_error_count` | integer | Count of row-level errors (severity = error) |
| `row_warning_count` | integer | Count of row-level warnings (severity = warning) |
| `notice_count` | integer | Count of informational notices |
| `has_zip` | boolean | Whether a ZIP file was included |
| `missing_files_count` | integer | Count of referenced files not found in ZIP |
| `error_types` | array | e.g. `["missing_required_fields", "missing_files", "row_errors"]` |
| `warning_types` | array | e.g. `["unrecognized_fields", "empty_columns", "row_warnings", "notices"]` |

**Example queries:**

```ruby
# Validation pass/fail breakdown
ImportMetric.validations.in_range(from, to)
  .group("payload->>'outcome'")
  .count
# => {"pass" => 80, "pass_with_warnings" => 30, "fail" => 40}

# Average validation duration
ImportMetric.validations.in_range(from, to)
  .average("(payload->>'duration_ms')::integer")

# Most common error types
ImportMetric.find_by_sql([<<-SQL, from, to])
  SELECT elem AS error_type, COUNT(*) AS cnt
  FROM bulkrax_import_metrics,
       jsonb_array_elements_text(payload->'error_types') AS elem
  WHERE metric_type = 'validation'
    AND created_at BETWEEN ? AND ?
  GROUP BY elem
  ORDER BY cnt DESC
SQL

# Most common warning types
ImportMetric.find_by_sql([<<-SQL, from, to])
  SELECT elem AS warning_type, COUNT(*) AS cnt
  FROM bulkrax_import_metrics,
       jsonb_array_elements_text(payload->'warning_types') AS elem
  WHERE metric_type = 'validation'
    AND created_at BETWEEN ? AND ?
  GROUP BY elem
  ORDER BY cnt DESC
SQL

# Validations that had missing files
ImportMetric.validations.in_range(from, to)
  .where("(payload->>'missing_files_count')::integer > 0")
  .count
```

---

### 3. Import Outcome (`metric_type = 'import_outcome'`)

Recorded server-side when an import run finishes (after all entries are processed).

**Event:** `import_complete`

| Payload Key | Type | Description |
|---|---|---|
| `outcome` | string | `"complete"`, `"partial"`, or `"failed"` |
| `total_work_entries` | integer | Total work entries in the run |
| `total_collection_entries` | integer | Total collection entries |
| `total_file_set_entries` | integer | Total file set entries |
| `processed_works` | integer | Successfully processed works |
| `failed_works` | integer | Failed works |
| `failed_records` | integer | Total failed records |
| `duration_seconds` | integer | Wall-clock time from run start to finish |
| `is_first_attempt` | boolean | Whether this was the importer's first run |
| `used_guided_import` | boolean | Whether the import was created via guided import |

**Example queries:**

```ruby
# Total imports in period
ImportMetric.import_outcomes.in_range(from, to).count

# First-attempt success rate
outcomes = ImportMetric.import_outcomes.in_range(from, to)
  .where("payload->>'is_first_attempt' = ?", 'true')
total = outcomes.count
successes = outcomes.where("payload->>'outcome' = ?", 'complete').count
rate = (successes.to_f / total * 100).round(1)

# Guided-import-only outcomes
ImportMetric.import_outcomes.in_range(from, to)
  .where("payload->>'used_guided_import' = ?", 'true')
  .group("payload->>'outcome'")
  .count

# Imports over time (by day and outcome)
ImportMetric.import_outcomes.in_range(from, to)
  .group("date_trunc('day', created_at)")
  .group("payload->>'outcome'")
  .count

# Average import duration
ImportMetric.import_outcomes.in_range(from, to)
  .average("(payload->>'duration_seconds')::integer")

# Recent imports with associations
ImportMetric.import_outcomes.in_range(from, to)
  .order(created_at: :desc)
  .limit(50)
  .includes(:importer, :user)
```

---

### 4. Feedback (`metric_type = 'feedback'`)

Recorded client-side when a user submits a Single Ease Question (SEQ) rating after import.

**Event:** `seq_rating`

| Payload Key | Type | Description |
|---|---|---|
| `seq_rating` | integer | 1-7 rating (1 = very difficult, 7 = very easy) |
| `comment` | string | Optional free-text comment |
| `importer_id` | integer | ID of the importer that was just created |

**Example queries:**

```ruby
# Average SEQ rating
ImportMetric.feedback.in_range(from, to)
  .average("(payload->>'seq_rating')::integer")

# SEQ distribution (how many 1s, 2s, 3s, etc.)
ImportMetric.feedback.in_range(from, to)
  .group("(payload->>'seq_rating')::integer")
  .count
# => {1 => 2, 3 => 5, 5 => 20, 6 => 15, 7 => 30}

# Response rate
total_imports = ImportMetric.import_outcomes.in_range(from, to).count
total_feedback = ImportMetric.feedback.in_range(from, to).count
response_rate = (total_feedback.to_f / total_imports * 100).round(1)

# Recent comments
ImportMetric.feedback.in_range(from, to)
  .where("payload->>'comment' IS NOT NULL")
  .where("payload->>'comment' != ''")
  .order(created_at: :desc)
  .limit(20)
  .pluck(:payload, :created_at)
  .map { |p, t| { rating: p['seq_rating'], comment: p['comment'], date: t } }
```

---

### 5. Timing (`metric_type = 'timing'`)

Recorded client-side at submit time. Captures how long the user spent on each step.

**Event:** `session_complete`

| Payload Key | Type | Description |
|---|---|---|
| `total_session_ms` | integer | Total time from step 1 load to submit |
| `step1_duration_ms` | integer | Time spent on step 1 (upload & validate) |
| `step2_duration_ms` | integer | Time spent on step 2 (review & configure) |
| `step3_duration_ms` | integer | Time spent on step 3 (confirm & import) |

**Example queries:**

```ruby
# Average total session time
ImportMetric.timing.in_range(from, to)
  .average("(payload->>'total_session_ms')::integer")

# Average time per step
(1..3).map do |step|
  avg = ImportMetric.timing.in_range(from, to)
    .average("(payload->>'step#{step}_duration_ms')::integer")
  [step, avg&.round(0)]
end.to_h
# => {1 => 45000, 2 => 12000, 3 => 8000}
```

---

## Cross-Metric Queries Using session_id

The `session_id` column links all metrics from a single guided import session. This enables correlation queries across metric types.

### Validation outcome vs. import outcome

```ruby
# Do validations that pass with warnings lead to more import failures?
ImportMetric.find_by_sql([<<-SQL, from, to])
  SELECT
    v.payload->>'outcome' AS validation_outcome,
    o.payload->>'outcome' AS import_outcome,
    COUNT(*) AS cnt
  FROM bulkrax_import_metrics v
  JOIN bulkrax_import_metrics o ON v.session_id = o.session_id
  WHERE v.metric_type = 'validation'
    AND v.event = 'validation_complete'
    AND o.metric_type = 'import_outcome'
    AND o.event = 'import_complete'
    AND v.session_id IS NOT NULL
    AND v.created_at BETWEEN ? AND ?
  GROUP BY v.payload->>'outcome', o.payload->>'outcome'
  ORDER BY validation_outcome, import_outcome
SQL
```

### Full session timeline

```ruby
# All metrics for a specific session
session = 'gi_a1b2c3d4e'
ImportMetric.where(session_id: session).order(:created_at)
```

### Sessions that validated but never submitted

```ruby
# Find sessions with validation but no import outcome
ImportMetric.find_by_sql([<<-SQL, from, to])
  SELECT v.session_id, v.payload->>'outcome' AS validation_outcome
  FROM bulkrax_import_metrics v
  LEFT JOIN bulkrax_import_metrics o
    ON v.session_id = o.session_id AND o.metric_type = 'import_outcome'
  WHERE v.metric_type = 'validation'
    AND v.event = 'validation_complete'
    AND o.id IS NULL
    AND v.session_id IS NOT NULL
    AND v.created_at BETWEEN ? AND ?
SQL
```

---

## Using MetricsAggregator

For common queries, use the service object instead of writing raw SQL:

```ruby
agg = Bulkrax::MetricsAggregator.new(from: 30.days.ago, to: Time.current)

agg.total_imports                    # Count of completed imports
agg.first_attempt_success_rate       # Percentage (e.g. 85.2)
agg.avg_validation_duration_ms       # Average validation time in ms
agg.validation_outcomes              # {"pass" => N, "fail" => N, ...}
agg.funnel_data                      # {1 => N, 2 => N, 3 => N}
agg.error_type_frequencies           # Top 10 error types with counts
agg.avg_seq_rating                   # Average SEQ score (1-7)
agg.seq_distribution                 # {1 => N, 2 => N, ...7 => N}
agg.seq_response_count               # Total feedback submissions
agg.recent_comments(limit: 20)       # [{rating:, comment:, date:}, ...]
agg.imports_over_time                # {[date, outcome] => count}
agg.recent_imports(limit: 50)        # ImportMetric records with associations
agg.validation_to_outcome_correlation # Validation vs import outcome matrix
agg.export_rows                      # All metrics as hashes (for CSV export)
```

---

## CSV Export

The dashboard provides a CSV export at `GET /importers/guided_import/metrics/export?from=YYYY-MM-DD&to=YYYY-MM-DD`.

Columns: `id`, `metric_type`, `event`, `importer_id`, `user_id`, `session_id`, `created_at`, `payload` (JSON string).
