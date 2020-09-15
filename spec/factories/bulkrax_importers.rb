# frozen_string_literal: true

FactoryBot.define do
  factory :bulkrax_importer, class: 'Bulkrax::Importer' do
    name { "A.N. Import" }
    admin_set_id { "MyString" }
    user { FactoryBot.build(:base_user) }
    frequency { "PT0S" }
    parser_klass { "Bulkrax::OaiDcParser" }
    limit { 10 }
    parser_fields { {} }
    field_mapping { [{}] }
  end

  factory :bulkrax_importer_oai, class: 'Bulkrax::Importer' do
    name { 'Oai Collection' }
    admin_set_id { 'MyString' }
    user { FactoryBot.build(:base_user) }
    frequency { 'PT0S' }
    parser_klass { 'Bulkrax::OaiDcParser' }
    limit { 10 }
    parser_fields do
      {
        'base_url' => 'http://commons.ptsem.edu/api/oai-pmh',
        'metadata_prefix' => 'oai_dc'
      }
    end
    field_mapping { {} }
  end

  factory :bulkrax_importer_csv, class: 'Bulkrax::Importer' do
    name { 'CSV Import' }
    admin_set_id { 'MyString' }
    user { FactoryBot.build(:base_user) }
    frequency { 'PT0S' }
    parser_klass { 'Bulkrax::CsvParser' }
    limit { 10 }
    parser_fields { { 'import_file_path' => 'spec/fixtures/csv/good.csv' } }
    field_mapping { {} }
    after :create, &:current_run
  end

  factory :bulkrax_importer_csv_complex, class: 'Bulkrax::Importer' do
    name { 'CSV Import' }
    admin_set_id { 'MyString' }
    user { FactoryBot.build(:base_user) }
    frequency { 'PT0S' }
    parser_klass { 'Bulkrax::CsvParser' }
    limit { 10 }
    parser_fields { { 'import_file_path' => 'spec/fixtures/csv/complex.csv' } }
    field_mapping { {} }
  end

  factory :bulkrax_importer_bagit, class: 'Bulkrax::Importer' do
    name { 'Bagit Import' }
    admin_set_id { 'MyString' }
    user { FactoryBot.build(:base_user) }
    frequency { 'PT0S' }
    parser_klass { 'Bulkrax::BagitParser' }
    limit { 10 }
    parser_fields do
      {
        'import_file_path' => 'spec/fixtures/bags/bag',
        'metadata_file_name' => 'descMetadata.nt',
        'metadata_format' => 'Bulkrax::RdfEntry'
      }
    end
    field_mapping { {} }
    after :create, &:current_run
  end

  factory :bulkrax_importer_csv_bad, class: 'Bulkrax::Importer' do
    name { 'CSV Import' }
    admin_set_id { 'MyString' }
    user { FactoryBot.build(:base_user) }
    frequency { 'PT0S' }
    parser_klass { 'Bulkrax::CsvParser' }
    limit { 10 }
    parser_fields { { 'import_file_path' => 'spec/fixtures/csv/bad.csv' } }
    field_mapping { {} }
  end

  factory :bulkrax_importer_csv_failed, class: 'Bulkrax::Importer' do
    name { 'CSV Import' }
    admin_set_id { 'MyString' }
    user { FactoryBot.build(:base_user) }
    frequency { 'PT0S' }
    parser_klass { 'Bulkrax::CsvParser' }
    limit { 10 }
    parser_fields { { 'import_file_path' => 'spec/fixtures/csv/failed.csv' } }
    field_mapping { {} }
  end

  factory :bulkrax_importer_xml, class: 'Bulkrax::Importer' do
    name { 'XML Import' }
    admin_set_id { 'MyString' }
    user { FactoryBot.build(:base_user) }
    frequency { 'PT0S' }
    parser_klass { 'Bulkrax::XmlParser' }
    limit { 10 }
    parser_fields { { 'import_file_path' => 'spec/fixtures/xml/good.xml' } }
    field_mapping do
      {
        'title': { from: ['TitleLargerEntity'] },
        'abstract': { from: ['Abstract'] }
      }
    end
  end
end
