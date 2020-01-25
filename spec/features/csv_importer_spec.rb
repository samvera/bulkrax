# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Importing from a CSV' do
    let(:importer) { FactoryBot.build(:bulkrax_importer_csv) }

    it 'creates a work' do
      importer.import_works
    end
  end
end
