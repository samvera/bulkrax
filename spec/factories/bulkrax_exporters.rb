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
    generated_metadata { false }

    trait :with_relationships_mappings do
      field_mapping do
        {
          'parents' => { 'from' => ['parents_column'], split: /\s*[|]\s*/, related_parents_field_mapping: true },
          'children' => { 'from' => ['children_column'], split: /\s*[|]\s*/, related_children_field_mapping: true }
        }
      end
    end
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
    generated_metadata { false }
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
    generated_metadata { false }
  end

  trait :all do
    name { 'Export from All' }
    export_type { 'metadata' }
    export_from { 'all' }
    export_source { nil }
  end
end
