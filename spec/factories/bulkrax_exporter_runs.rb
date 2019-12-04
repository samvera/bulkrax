FactoryBot.define do
  factory :bulkrax_exporter_run, class: 'Bulkrax::ExporterRun' do
    exporter { nil }
    total_work_entries { 1 }
    enqueued_records { 1 }
    processed_records { 1 }
    deleted_records { 1 }
    failed_records { 1 }
  end
end
