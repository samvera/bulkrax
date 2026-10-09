# frozen_string_literal: true

RSpec.shared_examples 'persisted Bulkrax serialization' do
  it 'round trips JSON importer and exporter settings' do
    [Bulkrax::Importer, Bulkrax::Exporter].each do |model|
      record = model.new(name: 'Smoke', parser_klass: 'Bulkrax::CsvParser', parser_fields: { 'limit' => 12 }, field_mapping: { 'title' => { 'from' => ['title'] } })
      record.save!(validate: false)
      expect(record.reload.parser_fields).to eq('limit' => 12)
      expect(record.field_mapping).to eq('title' => { 'from' => ['title'] })
    end
  end

  it 'round trips normalized metadata and collection arrays' do
    record = Bulkrax::CsvEntry.new(parsed_metadata: { 'title' => ['Smoke'] }, raw_metadata: { 'title' => 'Smoke' }, collection_ids: ['collection-1'])
    record.save!(validate: false)
    expect(record.reload.parsed_metadata).to eq('title' => ['Smoke'])
    expect(record.raw_metadata).to eq('title' => 'Smoke')
    expect(record.collection_ids).to eq(['collection-1'])
  end

  it 'round trips error backtraces' do
    record = Bulkrax::Status.new(error_backtrace: ['smoke.rb:1'])
    record.save!(validate: false)
    expect(record.reload.error_backtrace).to eq(['smoke.rb:1'])
  end
end
