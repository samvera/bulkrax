# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Importing an oai feed' do
    let(:importer) do
      f = FactoryBot.build(:bulkrax_importer_oai)
      f.user = User.new(email: 'test@example.com')
      f.save
      f
    end
    let(:collection) { FactoryBot.build(:collection) }

    around do |sample|
      Bulkrax.source_identifier_field_mapping = { 'Bulkrax::OaiDcEntry' => 'identifier' }
      sample.run
      Bulkrax.source_identifier_field_mapping = {}
    end

    it 'creates a work' do
      allow(Collection).to receive(:where).and_return([collection])
      importer.import_works
    end
  end
end
