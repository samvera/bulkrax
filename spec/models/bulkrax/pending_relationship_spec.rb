# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe PendingRelationship, type: :model do
    subject(:pending_relationship) { FactoryBot.create(:pending_relationship) }

    it 'is valid with valid attributes' do
      expect(pending_relationship).to be_valid
    end

    it 'belongs to an importer run' do
      expect(pending_relationship.importer_run).to be_a(Bulkrax::ImporterRun)
    end

    describe '.ordered' do
      it 'returns records ordered by the order column' do
        run = FactoryBot.create(:bulkrax_importer_run)
        r2 = FactoryBot.create(:pending_relationship, importer_run: run, order: 2)
        r1 = FactoryBot.create(:pending_relationship, importer_run: run, order: 1)
        expect(described_class.where(importer_run: run).ordered).to eq([r1, r2])
      end
    end
  end
end
