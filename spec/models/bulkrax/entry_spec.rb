require 'rails_helper'

module Bulkrax
  RSpec.describe Entry, type: :model do
    describe 'field_mappings' do
      let(:importer) { FactoryBot.build(:bulkrax_importer) }
      subject { described_class.new(importerexporter: importer) }

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

        it 'returns creator' do
          expect(subject.field_to('author')).to eq(['creator'])
        end

        it 'returns field when key exists, but no from mapping' do
          expect(subject.field_to('title')).to eq(['title'])
        end

        it 'returns field when field is not mapped but is supported' do
          expect(subject.field_to('publisher')).to eq([])
        end

        it 'returns nothing when the field is not supported' do
          expect(subject.field_to('unmapped_field')).to eq([])
        end
      end

      context '.field_supported?' do
        it 'returns true if the field is supported' do
          expect(subject.field_supported?('creator'))
        end

        it 'returns false if the field is not supported' do
          expect(subject.field_supported?('unsupported_field'))
        end
      end
    end
  end
end
