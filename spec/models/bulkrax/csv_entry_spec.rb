require 'rails_helper'

module Bulkrax
  RSpec.describe CsvEntry, type: :model do
    describe 'builds entry' do
      let(:importer) { FactoryBot.build(:bulkrax_importer_csv) }
      subject { described_class.new(importerexporter: importer) }

      before do
        allow(Bulkrax).to receive(:default_work_type).and_return('Work')
      end

      context 'without required metadata' do
        before(:each) do
          allow(subject).to receive(:record).and_return(source_identifier: '1', some_field: 'some data')
        end

        it 'fails and stores an error' do
          subject.identifier = 1
          expect { subject.build_metadata }.to raise_error(StandardError)
        end
      end

      context 'with required metadata' do
        before(:each) do
          class WorkFactory < ObjectFactory
            include WithAssociatedCollection
            self.klass = Work
            self.system_identifier_field = Bulkrax.system_identifier_field
          end
          allow_any_instance_of(WorkFactory).to receive(:run)
          allow_any_instance_of(User).to receive(:batch_user)
          allow(subject).to receive(:record).and_return('source_identifier' => '2', 'title' => 'some title')
        end

        it 'succeeds' do
          subject.identifier = 2
          subject.build
          expect(subject.status).to eq('succeeded')
        end
      end
    end
  end
end
