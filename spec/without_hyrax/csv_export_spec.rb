# frozen_string_literal: true

return unless ENV['BULKRAX_WITH_HYRAX'] == 'false'

require 'csv'
require_relative 'support/app_without_hyrax'

RSpec.describe 'Exporting a CSV without Hyrax' do
  include_context 'a Bulkrax app without Hyrax'

  def export(**attributes)
    exporter = Bulkrax::Exporter.create!(name: 'CSV export', user: user, parser_klass: 'Bulkrax::CsvParser',
                                         export_type: 'metadata', limit: 0, parser_fields: {},
                                         field_mapping: Bulkrax.field_mappings['Bulkrax::CsvParser'], **attributes)
    Bulkrax::ExporterJob.perform_now(exporter.id)
    exporter.reload
  end

  def exported_rows(exporter)
    path = Dir.glob(File.join(exporter.exporter_export_path, '**', '*.csv')).first
    CSV.read(path, headers: true).map(&:to_h)
  end

  let(:exported_works) do
    [
      { 'bulkrax_identifier' => 'work-1', 'model' => 'Work', 'title' => 'First work', 'creator_1' => 'Ada', 'creator_2' => 'Grace', 'visibility' => 'open' },
      { 'bulkrax_identifier' => 'work-2', 'model' => 'Work', 'title' => 'Second work', 'creator_1' => 'Alan', 'creator_2' => nil, 'visibility' => 'open' }
    ]
  end

  before do
    import(<<~CSV)
      bulkrax_identifier,title,creator
      work-1,First work,Ada;Grace
      work-2,Second work,Alan
    CSV
  end

  it 'exports the works an importer created' do
    exporter = export(export_from: 'importer', export_source: Bulkrax::Importer.last.id.to_s)

    expect(exported_rows(exporter).map { |row| row.except('id') }).to eq(exported_works)
    expect(exporter.status).to eq('Complete')
  end

  it 'exports every work' do
    exporter = export(export_from: 'all', export_source: '')

    expect(exported_rows(exporter).map { |row| row.except('id') }).to match_array(exported_works)
    expect(exporter.status).to eq('Complete')
  end
end
