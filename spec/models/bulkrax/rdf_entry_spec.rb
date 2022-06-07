# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe RdfEntry, type: :model do
    subject { described_class.new(importerexporter: importer) }
    let(:path) { './spec/fixtures/bags/bag/descMetadata.nt' }
    let(:data) { described_class.read_data(path) }
    let(:importer) do
      i = FactoryBot.create(:bulkrax_importer_bagit_rdf,
                            parser_fields: {
                              'import_file_path' => './spec/fixtures/bags/bag',
                              'metadata_file_name' => 'descMetadata.nt',
                              'metadata_format' => 'Bulkrax::RdfEntry'
                            },
                            field_mapping: {
                              'identifier' => { from: ['http://purl.org/dc/terms/identifier'] },
                              'title' => { from: ['http://purl.org/dc/terms/title'] }
                            })
      i.current_run
      i
    end

    describe 'class methods' do
      it 'reads the data' do
        expect(described_class.read_data(path)).to be_a(RDF::NTriples::Reader)
      end

      it 'retrieves the fields (predicates)' do
        expect(described_class.fields_from_data(data)).to eq(["http://purl.org/dc/terms/identifier", "http://purl.org/dc/terms/title"])
      end

      it 'retrieves the data and constructs a hash' do
        expect(described_class.data_for_entry(data, :source_identifier, subject.parser)).to eq(
          data: "<http://example.org/ns/19158> <http://purl.org/dc/terms/identifier> \"12345\" .\n<http://example.org/ns/19158> <http://purl.org/dc/terms/title> \"Test Bag\" .\n",
          delete: nil,
          children: [],
          collection: [],
          format: :ntriples,
          source_identifier: "http://example.org/ns/19158"
        )
      end
    end

    describe 'builds entry' do
      let(:raw_metadata) { described_class.data_for_entry(data, :source_identifier, subject.parser) }

      context 'deleted' do
        let(:path) { './spec/fixtures/bags/deleted_bag/descMetadata.nt' }

        it 'has a deleted proeprty' do
          expect(raw_metadata[:delete]).to be_truthy
        end
      end

      context 'with raw_metadata' do
        before do
          subject.raw_metadata = raw_metadata
          subject.identifier = "http://example.org/ns/19158"
          allow_any_instance_of(ObjectFactory).to receive(:run!).and_return(instance_of(Work))
          allow(User).to receive(:batch_user)
        end

        it 'succeeds' do
          subject.build
          expect(subject.parsed_metadata).to eq("file" => nil, "rights_statement" => [nil], "source" => ["http://example.org/ns/19158"], "title" => ["Test Bag"], "visibility" => "open", "admin_set_id" => "MyString")
          expect(subject.status).to eq('Complete')
        end

        it 'has a nil delete' do
          expect(subject.raw_metadata[:delete]).to be_nil
        end
      end

      context 'without raw_metadata' do
        before do
          subject.raw_metadata = nil
          subject.identifier = "http://example.org/ns/19158"
        end

        it 'fails' do
          subject.build
          expect(subject.status).to eq('Failed')
        end
      end
    end
  end
end
