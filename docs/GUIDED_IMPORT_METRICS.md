# Guided Import Metrics

Bulkrax can record how people use the guided import: which steps they reach, how validation turns out, how each import run finishes, and how easy they found it. Administrators see the results on a dashboard and can export them as CSV.

## Enabling

Metrics are off by default. Turn them on with an environment variable:

```
BULKRAX_GUIDED_IMPORT_METRICS=true
```

or in an initializer:

```ruby
Bulkrax.setup do |config|
  config.guided_import_metrics_enabled = true
end
```

When the setting is off, nothing is recorded, the metrics endpoints return 404, and the guided import shows no feedback form.

The dashboard is restricted by an ability method the host application defines. Without it, every user is denied:

```ruby
# app/models/ability.rb
def can_read_bulkrax_metrics?
  admin?
end
```

Run your database migrations after upgrading. Bulkrax's migration creates the `bulkrax_import_metrics` table.

## Dashboard

With metrics enabled, a "Guided Import Metrics" link appears in the dashboard sidebar for users who pass `can_read_bulkrax_metrics?`. The page (`/importers/metrics`) covers a date range, the last 30 days by default, and shows:

- **Summary:** import runs, first-attempt success rate, average validation time, and average ease-of-use rating.
- **Imports by day:** runs that finished `Complete` and those with any other outcome.
- **Validation accuracy:** how each first import attempt turned out, grouped by the last validation result in the same session. First attempts with no validation in their session, including imports created before metrics were turned on, appear as "Validation skipped".
- **Import funnel:** how many sessions reached each step.
- **Most common validation errors.**
- **Ease-of-use ratings:** the distribution of 1 to 7 ratings and recent comments.
- **Recent guided imports:** each run's recorded outcome, record count, and whether it was the first attempt.

**Export CSV** downloads every metric in the range. Cells that begin with `=`, `+`, `-`, `@`, a tab or a carriage return are prefixed with `'` so spreadsheets do not run them as formulas.

## What is recorded

Every metric is one row in `bulkrax_import_metrics`. Fields that the dashboard queries are columns; other detail is JSON in `payload`. Rows carry the `session_id` of the guided import page that produced them, so one person's pass through the wizard can be followed from step to outcome.

| `metric_type` | Recorded by | Columns used | `payload` |
|---|---|---|---|
| `funnel` | Browser, once per step per session | `step` (1 to 4; 4 means the import was created) | |
| `timing` | Browser, when the import is created | `duration_ms` (whole session) | `step1`, `step2`, `step3`: milliseconds spent on each step |
| `feedback` | Browser, when a rating is sent | `rating` (1 to 7), `importer_id` | `comment` (at most 1,000 characters) |
| `validation` | Server, on each validation | `outcome` (`pass`, `pass_with_warnings`, `fail`), `duration_ms` | Counts of each problem, `error_types`, `warning_types` |
| `import_outcome` | Server, when a run finishes or fails | `outcome` (the importer status, such as `Complete` or `Failed`), `first_attempt`, `duration_ms`, `importer_id`, `importer_run_id` | Entry totals and failure counts for the run |

Outcomes are recorded only for importers created through the guided import, and each run has exactly one outcome row. The row stores the status the run finished with, so later re-runs do not change it. `first_attempt` is true only for an importer's earliest run.

The browser endpoint accepts only `funnel`, `timing` and `feedback`, each limited to its own fields. It requires a signed-in user who can import, and a CSRF token.

Deleting an importer keeps its metrics and clears `importer_id` and `importer_run_id`.

## Querying from a console

The dashboard figures come from `Bulkrax::MetricsAggregator`, which is the simplest way to get them:

```ruby
metrics = Bulkrax::MetricsAggregator.new(from: 30.days.ago, to: Time.current)
metrics.first_attempt_success_rate # => 82.5
metrics.validation_accuracy        # => { "pass" => { "Complete" => 40, "Failed" => 2 }, ... }
metrics.funnel                     # => { 1 => 120, 2 => 95, 3 => 90, 4 => 84 }
```

The model has scopes for the server-recorded types and for date ranges:

```ruby
Bulkrax::ImportMetric.import_outcomes.in_range(30.days.ago, Time.current).group(:outcome).count
Bulkrax::ImportMetric.validations.where(outcome: 'fail').average(:duration_ms)
Bulkrax::ImportMetric.where(metric_type: 'feedback', rating: 1..3).order(created_at: :desc).limit(10).map { |m| m.payload['comment'] }
```

These queries use only standard columns, so they work on any database Bulkrax supports.
