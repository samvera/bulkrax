# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe XmlEntry, type: :model do
    let(:path) { './spec/fixtures/xml/single.xml' }
    let(:data) { described_class.read_data(path) }

    before do
      Bulkrax.source_identifier_field_mapping = { 'Bulkrax::XmlEntry' => 'DrisUnique' }
    end

    describe 'class methods' do
      context '#read_data' do
        it 'reads the data from an xml file' do
          expect(described_class.read_data(path)).to be_a(Nokogiri::XML::Document)
        end
      end

      context '#data_for_entry' do
        it 'retrieves the data and constructs a hash' do
          expect(described_class.data_for_entry(data)).to eq(
            source_identifier: '3456012',
            data: "<!-- This grammar has been deprecated - use FMPXMLRESULT instead --><FMPDSORESULT> <ROW MODID=\"3\" RECORDID=\"000003\"> <TitleLargerEntity>Single XML Entry</TitleLargerEntity> <Abstract>Lorem ipsum dolor sit amet.</Abstract> <DrisUnique>3456012</DrisUnique> </ROW></FMPDSORESULT>",
            collection: [],
            file: [],
            children: []
          )
        end
      end
    end

    describe '#build' do
      subject { described_class.new(importerexporter: importer) }
      let(:raw_metadata) { described_class.data_for_entry(data) }
      let(:importer) { FactoryBot.build(:bulkrax_importer_xml) }

      before do
        Bulkrax.default_work_type = 'Work'
        Bulkrax.field_mappings.merge!({
          'Bulkrax::XmlParser' => {
            'title' => { from: ['TitleLargerEntity'] },
            'abstract' => { from: ['Abstract'] }
          }
        })
      end

      context 'with raw_metadata' do
        before do
          subject.raw_metadata = raw_metadata
          allow_any_instance_of(ObjectFactory).to receive(:run).and_return(instance_of(Work))
          allow(User).to receive(:batch_user)
        end

        it 'succeeds' do
          subject.build
          expect(subject.status).to eq('succeeded')
        end

        it 'builds entry' do
          subject.build
          expect(subject.parsed_metadata).to eq("file" => [], "rights_statement" => [nil], "source" => ["3456012"], "title" => ["Single XML Entry"], "visibility" => "open")
        end

        it 'does not add unsupported fields' do
          subject.build
          expect(subject.parsed_metadata).not_to include('abstract')
          expect(subject.parsed_metadata).not_to include('Lorem ipsum dolor sit amet.')
        end
      end

      context 'without raw_metadata' do
        before do
          subject.raw_metadata = nil
        end

        it 'fails' do
          subject.build
          expect(subject.status).to eq('failed')
        end
      end
    end
  end
end
