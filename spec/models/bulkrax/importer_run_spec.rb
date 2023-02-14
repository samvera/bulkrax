# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImporterRun, type: :model do
    let(:importer_run) { build(:bulkrax_importer_run) }

    describe '#parents' do
      subject { importer_run.parents }

      it { is_expected.to be_an(Array) }
    end

    describe '#user' do
      subject { importer_run.user }

      it { is_expected.to be_a(User) }
    end

    context 'when being destroyed' do
      before do
        importer_run.save
        create(:pending_relationship_collection_parent, importer_run_id: importer_run.id)
        create(:pending_relationship_work_parent, importer_run_id: importer_run.id)
      end

      it 'destroys all of its associated pending relationships' do
        expect { importer_run.destroy }.to change(PendingRelationship, :count).by(-2)
      end
    end
  end
end
