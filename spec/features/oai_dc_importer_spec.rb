# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Importing an oai feed' do
    let(:importer) { FactoryBot.build(:bulkrax_importer_oai) }

    it 'creates a work' do
      expect(importer).to receive(:import_objects)
      importer.import_works
    end
  end
end
