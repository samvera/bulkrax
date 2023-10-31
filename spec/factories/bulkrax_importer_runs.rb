# frozen_string_literal: true

FactoryBot.define do
  factory :bulkrax_importer_run, class: 'Bulkrax::ImporterRun' do
    importer { FactoryBot.build(:bulkrax_importer) }
    total_work_entries { 1 }
    enqueued_records { 1 }
    processed_records { 0 }
    deleted_records { 0 }
    failed_records { 0 }
  end
end
