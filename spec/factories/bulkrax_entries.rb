FactoryBot.define do
  factory :bulkrax_entry, class: 'Bulkrax::Entry' do
    identifier { "MyString" }
    type { "" }
    importerexporter { FactoryBot.build(:bulkrax_importer) }
    raw_metadata { "MyText" }
    parsed_metadata { "MyText" }
  end
end
