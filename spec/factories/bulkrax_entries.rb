FactoryBot.define do
  factory :bulkrax_entry, class: 'Bulkrax::Entry' do
    identifier { "MyString" }
    type { 'Bulkrax::Entry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { "MyText" }
    parsed_metadata { "MyText" }
  end

  factory :bulkrax_csv_entry, class: 'Bulkrax::CsvEntry' do
    identifier { "MyString" }
    type { 'Bulkrax::CsvEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end

  factory :bulkrax_rdf_entry, class: 'Bulkrax::RdfEntry' do
    identifier { "MyString" }
    type { 'Bulkrax::RdfEntry' }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { {} }
    parsed_metadata { {} }
  end
end
