# frozen_string_literal: true

FactoryBot.define do
  factory :bulkrax_exporter, class: 'Bulkrax::Exporter' do
    name { 'Export from Importer' }
    user { FactoryBot.build(:base_user) }
    export_type { "metadata" }
    export_from { 'importer' }
    export_source { '1' }
    parser_klass { "Bulkrax::CsvParser" }
    limit { 0 }
    field_mapping { nil }
  end

  factory :bulkrax_exporter_collection, class: 'Bulkrax::Exporter' do
    name { "Export from Collection" }
    user { FactoryBot.build(:base_user) }
    export_type { "full" }
    export_from { "collection" }
    export_source { '12345' }
    parser_klass { "Bulkrax::CsvParser" }
    limit { 0 }
    field_mapping { nil }
  end

  factory :bulkrax_exporter_worktype, class: 'Bulkrax::Exporter' do
    name { 'Export from Worktype' }
    user { FactoryBot.build(:base_user) }
    export_type { 'metadata' }
    export_from { 'worktype' }
    export_source { 'Generic' }
    parser_klass { 'Bulkrax::CsvParser' }
    limit { 0 }
    field_mapping { nil }
  end
end
