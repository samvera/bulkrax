FactoryBot.define do
  factory :bulkrax_entry, class: 'Entry' do
    identifier { "MyString" }
    type { "" }
    importer { nil }
    raw_metadata { "MyText" }
    parsed_metadata { "MyText" }
  end
end
