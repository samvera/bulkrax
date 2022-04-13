# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImporterRun, type: :model do
    subject(:importer_run) { build(:bulkrax_importer_run) }

    describe '#parents' do
      it 'is an Array' do
        expect(importer_run.parents).to be_an(Array)
      end
    end
  end
end
