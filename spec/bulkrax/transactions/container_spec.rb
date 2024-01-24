# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Hyrax::Transactions::Container do
  describe 'work_resource.create_with_bulk_behavior' do
    subject(:transaction_step) { described_class['work_resource.create_with_bulk_behavior'] }

    describe '#steps' do
      subject { transaction_step.steps }
      it { is_expected.to include("work_resource.add_bulkrax_files") }
      it { is_expected.not_to include("work_resource.add_file_sets") }
    end
  end

  describe 'work_resource.update_with_bulk_behavior' do
    subject(:transaction_step) { described_class['work_resource.update_with_bulk_behavior'] }

    describe '#steps' do
      subject { transaction_step.steps }
      it { is_expected.to include("work_resource.add_bulkrax_files") }
      it { is_expected.not_to include("work_resource.add_file_sets") }
    end
  end

  describe 'work_resource.add_bulkrax_files' do
    subject(:transaction_step) { described_class['work_resource.add_bulkrax_files'] }

    it { is_expected.to be_a Bulkrax::Steps::AddFiles }
  end
end