require 'rails_helper'

module Bulkrax
  RSpec.describe Entry, type: :model do
    describe 'field_mappings' do
      let(:importer) { FactoryBot.build(:bulkrax_importer) }
      subject { described_class.new(importerexporter: importer) }

      before do
        allow(Bulkrax).to receive(:default_work_type).and_return('Work')
      end

      context '.mapping' do

        it 'is delegated to importer and returns the default set of 15 dc properties' do
          expect(subject.mapping.keys.length).to eq(15)
        end
      end

      context '.field_to (has_matchers)' do
        let(:importer) { 
          FactoryBot.build(:bulkrax_importer, field_mapping: { 
            'creator' => {
              from: ['author'],
              parsed: false,
              split: false,
              if: nil,
              excluded: false
              },
            'title' => {}
          })
        }

        it 'returns creator when author is mapped to creator' do
          expect(subject.field_to('author')).to eq(['creator'])
        end

        it 'returns field when key exists, but there is no from mapping' do
          expect(subject.field_to('title')).to eq(['title'])
        end

        it 'returns field when field is not mapped at all' do
          expect(subject.field_to('publisher')).to eq(['publisher'])
        end
      end

      context '.field_supported?' do
        it 'returns true if the field is supported' do
          expect(subject.field_supported?('title')).to be_truthy
        end

        it 'returns false if the field is not supported' do
          expect(subject.field_supported?('unsupported_field')).to be_falsey
        end
      end

      context 'factory_class' do
        it 'returns Work' do
          expect(subject.factory_class).to eq(Work)
        end
      end
    end
  end
end
