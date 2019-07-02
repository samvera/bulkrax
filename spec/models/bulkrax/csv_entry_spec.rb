require 'rails_helper'

module Bulkrax
  RSpec.describe CsvEntry, type: :model do
    describe 'builds entry' do
      let(:importer) { FactoryBot.build(:bulkrax_importer_csv) }
      subject { described_class.new(importer: importer) }

      context 'without required metadata' do
        before(:each) do
          allow(subject).to receive(:record).and_return(identifier: '1', some_field: 'some data')
        end

        it 'fails and stores an error' do
          subject.identifier = 1
          subject.build
          expect(subject.last_error).to start_with('Missing required elements, required elements are: title, identifier')
          expect(subject.status).to eq('failed')
        end
      end

      context 'with required metadata' do
        before(:each) do
          allow_any_instance_of(WorkFactory).to receive(:run)
          allow(subject).to receive(:record).and_return('identifier' => '2', 'title' => 'some title')
        end

        it 'succeeds' do
          subject.identifier = 2
          subject.build
          puts subject.last_error
          expect(subject.status).to eq('succeeded')
        end
      end
    end
  end
end
