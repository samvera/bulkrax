# frozen_string_literal: true

FactoryBot.define do
  factory :bulkrax_entry, class: 'Bulkrax::Entry' do
    identifier { "MyString" }
    type { 'Bulkrax::Entry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { "MyText" }
    parsed_metadata { "MyText" }
  end

  factory :bulkrax_csv_entry, class: 'Bulkrax::CsvEntry' do
    identifier { "csv_entry" }
    type { 'Bulkrax::CsvEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end

  factory :bulkrax_csv_entry_work, class: 'Bulkrax::CsvEntry' do
    identifier { "entry_work" }
    type { 'Bulkrax::CsvEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end

  factory :bulkrax_csv_entry_collection, class: 'Bulkrax::CsvEntry' do
    identifier { "entry_collection" }
    type { 'Bulkrax::CsvCollectionEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end

  factory :bulkrax_csv_another_entry_collection, class: 'Bulkrax::CsvEntry' do
    identifier { "another_entry_collection" }
    type { 'Bulkrax::CsvCollectionEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end

  factory :bulkrax_csv_entry_failed, class: 'Bulkrax::CsvEntry' do
    identifier { "entry_failed" }
    type { 'Bulkrax::CsvEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { { title: 'Title' } }
    parsed_metadata { {} }
    statuses { [association(:bulkrax_status, status_message: 'Failed')] }
  end

  factory :bulkrax_rdf_entry, class: 'Bulkrax::RdfEntry' do
    identifier { "MyString" }
    type { 'Bulkrax::RdfEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end

  factory :bulkrax_csv_entry_file_set, class: 'Bulkrax::CsvFileSetEntry' do
    identifier { 'file_set_entry_1' }
    type { 'Bulkrax::CsvFileSetEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end

  trait :with_file_set_metadata do
    raw_metadata do
      {
        'title' => 'FileSet Entry',
        'source_identifier' => 'file_set_entry_1',
        'file' => 'removed.png'
      }
    end
  end
end
