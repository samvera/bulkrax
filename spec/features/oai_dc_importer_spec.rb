require 'rails_helper'

module Bulkrax
  RSpec.describe 'Importing an oai feed' do
    let(:importer) {
      f = FactoryBot.build(:bulkrax_importer_oai)
      f.user = User.new(email: 'test@example.com')
      f.save
      f
    }

    it 'should create a work' do
      importer.import_works
    end
  end
end

