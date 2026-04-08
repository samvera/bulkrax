# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe Status, type: :model do
    subject(:status) { FactoryBot.create(:bulkrax_status) }

    it 'is valid with valid attributes' do
      expect(status).to be_valid
    end

    describe '#latest?' do
      it 'returns true for the most recent status for its statusable' do
        expect(status.latest?).to be true
      end

      it 'returns false for an earlier status' do
        earlier = FactoryBot.create(:bulkrax_status, statusable: status.statusable, runnable: status.runnable)
        expect(status.reload.latest?).to be false
        expect(earlier.latest?).to be true
      end
    end

    describe '.for_importers' do
      it 'returns statuses whose statusable_type is Bulkrax::Importer' do
        importer = FactoryBot.create(:bulkrax_importer)
        importer_status = FactoryBot.create(:bulkrax_status, statusable: importer)
        expect(described_class.for_importers).to include(importer_status)
        expect(described_class.for_importers).not_to include(status)
      end
    end

    describe '.for_exporters' do
      it 'returns statuses whose statusable_type is Bulkrax::Exporter' do
        exporter = FactoryBot.create(:bulkrax_exporter)
        exporter_status = FactoryBot.create(:bulkrax_status, statusable: exporter)
        expect(described_class.for_exporters).to include(exporter_status)
        expect(described_class.for_exporters).not_to include(status)
      end
    end
  end
end
