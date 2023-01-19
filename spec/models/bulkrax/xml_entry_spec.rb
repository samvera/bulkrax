# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe XmlEntry, type: :model do
    let(:path) { './spec/fixtures/xml/single.xml' }
    let(:data) { described_class.read_data(path) }
    let(:source_identifier) { :DrisUnique }
    let(:mappings) do
      {
        'title' => { from: ['TitleLargerEntity'] },
        'abstract' => { from: ['Abstract'] },
        'shape' => { from: ['shape'] },
        'source' => { from: [source_identifier.to_s], source_identifier: true }
      }
    end

    around do |spec|
      # The original specs were changing global state, which if we were to run specs in random order
      # could create odd results.  This change helps remove that pollution of global state; we could
      # still run into problems if we ever run our specs in parallel.
      original_mappings = Bulkrax.field_mappings['Bulkrax::XmlParser']
      Bulkrax.field_mappings['Bulkrax::XmlParser'] = mappings

      spec.run
      if original_mappings.nil?
        Bulkrax.field_mappings.delete('Bulkrax::XmlParser')
      else
        Bulkrax.field_mappings['Bulkrax::XmlParser'] = original_mappings
      end
    end

    describe 'class methods' do
      context '#read_data' do
        it 'reads the data from an xml file' do
          expect(described_class.read_data(path)).to be_a(Nokogiri::XML::Document)
        end
      end

      context '#data_for_entry' do
        it 'retrieves the data and constructs a hash' do
          expect(described_class.data_for_entry(data, source_identifier, nil)).to eq(
            DrisUnique: '3456012',
            delete: nil,
            data: "<!-- This grammar has been deprecated - use FMPXMLRESULT instead --><FMPDSORESULT> <ROW MODID=\"3\" RECORDID=\"000003\"> <TitleLargerEntity>Single XML Entry</TitleLargerEntity> <Abstract>Lorem ipsum dolor sit amet.</Abstract> <DrisUnique>3456012</DrisUnique> </ROW></FMPDSORESULT>",
            collection: [],
            children: []
          )
        end
      end
    end

    describe 'deleted' do
      subject(:xml_entry) { described_class.new(importerexporter: importer) }
      let(:path) { './spec/fixtures/xml/deleted.xml' }
      let(:raw_metadata) { described_class.data_for_entry(data, source_identifier, nil) }
      let(:importer) do
        i = FactoryBot.create(:bulkrax_importer_xml)
        i.current_run
        i
      end
      let(:object_factory) { instance_double(ObjectFactory) }

      it 'parses the delete as true if present' do
        expect(raw_metadata[:delete]).to be_truthy
      end
    end

    describe '#build' do
      subject(:xml_entry) { described_class.new(importerexporter: importer) }
      let(:raw_metadata) { described_class.data_for_entry(data, source_identifier, nil) }
      let(:importer) do
        i = FactoryBot.create(:bulkrax_importer_xml)
        i.field_mapping['source'] = { 'from' => ['DrisUnique'], 'source_identifier' => true }
        i.current_run
        i
      end
      let(:object_factory) { instance_double(ObjectFactory) }

      it 'parses the delete as nil if it is not present' do
        expect(raw_metadata[:delete]).to be_nil
      end

      context 'with raw_metadata' do
        before do
          xml_entry.raw_metadata = raw_metadata
          allow(ObjectFactory).to receive(:new).and_return(object_factory)
          allow(object_factory).to receive(:run!).and_return(instance_of(Work))
          allow(User).to receive(:batch_user)
        end

        it 'succeeds' do
          xml_entry.build
          expect(xml_entry.status).to eq('Complete')
        end

        it 'builds entry' do
          xml_entry.build
          expect(xml_entry.parsed_metadata).to eq("file" => nil, "rights_statement" => [nil], "source" => ["3456012"], "title" => ["Single XML Entry"], "visibility" => "open",
                                                  "admin_set_id" => "MyString")
        end

        it 'does not add unsupported fields' do
          xml_entry.build
          expect(xml_entry.parsed_metadata).not_to include('abstract')
          expect(xml_entry.parsed_metadata).not_to include('Lorem ipsum dolor sit amet.')
        end
      end

      context 'without raw_metadata' do
        before do
          xml_entry.raw_metadata = nil
        end

        it 'fails' do
          xml_entry.build
          expect(xml_entry.status).to eq('Failed')
        end
      end
    end

    describe '#build_metadata' do
      subject(:entry) { described_class.new(importerexporter: importer) }
      before do
        class ::Avacado < Work
          property :shape, predicate: ::RDF::Vocab::DC.format
        end
      end
      after do
        Object.send(:remove_const, :Avacado)
      end
      let(:importer) { FactoryBot.build(:bulkrax_importer_xml) }
      let(:raw_metadata) do
        %(<?xml version="1.0" encoding="UTF-8"?>) \
         "<entry>" \
         "<TitleLargerEntity>Green Friend for All</TitleLargerEntity>" \
         "<shape>Lumpy and Kind of Brown</shape>" \
         "<model>Avacado</model>" \
         "<DrisUnique>123</DrisUnique>" \
         "</entry>"
      end

      it "establishes the factory class before attempting to parse other fields" do
        entry.raw_metadata = { "data" => raw_metadata, "DrisUnique" => "123" }
        expect(entry.source_identifier).to eq("DrisUnique")
        expect(entry.parser.model_field_mappings).to eq(["model"])
        expect(entry.build_metadata)
        expect(entry.parsed_metadata["shape"]).to eq(["Lumpy and Kind of Brown"])
        expect(entry.parsed_metadata["title"]).to eq(["Green Friend for All"])
        expect(entry.factory_class).to eq(Avacado)
      end
    end
  end
end
