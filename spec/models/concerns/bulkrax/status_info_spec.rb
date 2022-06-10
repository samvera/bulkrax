# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe StatusInfo do
    subject(:status_info) { build(:bulkrax_status) }
    let(:record) { status_info.statusable }

    describe '#failed?' do
      before do
        allow(record).to receive(:current_status).and_return(status_info)
      end

      context 'when status_message is "Failed"' do
        before do
          status_info.status_message = 'Failed'
        end

        it 'returns true' do
          expect(record.failed?).to eq(true)
        end
      end

      context 'when status_message is "Complete (with failures)"' do
        before do
          status_info.status_message = 'Complete (with failures)'
        end

        it 'returns false' do
          expect(record.failed?).to eq(false)
        end
      end
    end
  end
end
