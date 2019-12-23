# frozen_string_literal: true

FactoryBot.define do
  factory :bulkrax_importer_run, class: 'Bulkrax::ImporterRun' do
    importer { FactoryBot.build(:bulkrax_importer) }
    total_work_entries { 1 }
    enqueued_records { 1 }
    processed_records { 1 }
    deleted_records { 1 }
    failed_records { 1 }
  end
end
