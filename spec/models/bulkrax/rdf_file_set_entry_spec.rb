# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe RdfFileSetEntry, type: :model do
    describe '#default_work_type' do
      subject { described_class.new.default_work_type }
      it { is_expected.to eq("::FileSet") }
    end

    describe '#factory_class' do
      subject { described_class.new.factory_class }
      it { is_expected.to eq(::FileSet) }
    end
  end
end
