# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'bulkrax/importers/_csv_fields.html.erb', type: :view do
  let(:importer) { FactoryBot.create(:bulkrax_importer_csv, parser_fields: { 'import_file_path' => 'spec/fixtures/csv/good.csv', 'create_new_records' => true }) }

  before { allow(Hyrax.config).to receive(:browse_everything?).and_return(false) }

  it 'checks the external source box for an importer saved with true, so saving the form keeps it' do
    html = view.simple_form_for(importer, url: '/importers') do |form|
      form.fields_for(:parser_fields) { |fi| view.render partial: 'bulkrax/importers/csv_fields', locals: { form: form, fi: fi, importer: importer } }
    end

    checkbox = Nokogiri::HTML(html).at_css('input[type=checkbox][name="importer[parser_fields][create_new_records]"]')
    expect(checkbox['checked']).to be_present
  end
end
