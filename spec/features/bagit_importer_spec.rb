# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe 'Importing from a CSV' do
    let(:importer) do
      FactoryBot.create(:bulkrax_importer_bagit)
    end

    it 'creates a work' do
      importer.current_run
      importer.import_works
    end
  end
end
