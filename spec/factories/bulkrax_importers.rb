FactoryBot.define do
  factory :bulkrax_importer, class: 'Bulkrax::Importer' do
    name { "MyString" }
    admin_set_id { "MyString" }
    user { nil }
    frequency { "PT0S" }
    parser_klass { "MyString" }
    limit { 1 }
    parser_fields { "" }
    field_mapping { "" }
  end

  factory :bulkrax_importer_oai, class: 'Bulkrax::Importer' do
    name { "Oai Collection" }
    admin_set_id { "MyString" }
    user { nil }
    frequency { "PT0S" }
    parser_klass { "Bulkrax::OaiDcParser" }
    limit { 10 }
    parser_fields { {
                      'base_url' =>  "http://commons.ptsem.edu/api/oai-pmh",
                      'metadata_prefix' => 'oai_dc'
                    }
    }
    field_mapping { "" }
  end

end
