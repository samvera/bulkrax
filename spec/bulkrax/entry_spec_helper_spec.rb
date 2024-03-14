# frozen_string_literal: true

require 'rails_helper'
require 'bulkrax/entry_spec_helper'
require 'byebug'

RSpec.describe Bulkrax::EntrySpecHelper do
  describe '.entry_for' do
    let(:identifier) { "867-5309" }
    let(:options) { {} }
    subject(:entry) { described_class.entry_for(identifier: identifier, data: data, parser_class_name: parser_class_name, **options) }

    context 'for parser_class_name: "Bulkrax::CsvParser"' do
      let(:parser_class_name) { "Bulkrax::CsvParser" }
      let(:import_file_path) { 'spec/fixtures/csv/good.csv' }
      let(:options) do
        {
          parser_fields: {
            # Columns are: model,source_identifier,title,parents_column
            'import_file_path' => import_file_path
          }
        }
      end

      context 'when ActiveFedora object' do
        let(:data) { { model: "Work", source_identifier: identifier, title: "If You Want to Go Far" } }

        before do
          allow(Bulkrax).to receive(:object_factory).and_return(Bulkrax::ObjectFactory)
        end

        it { is_expected.to be_a(Bulkrax::CsvEntry) }

        it "parses metadata" do
          entry.build_metadata

          expect(entry.factory_class).to eq(Work)
          {
            "title" => ["If You Want to Go Far"],
            "admin_set_id" => "admin_set/default",
            "source" => [identifier]
          }.each do |key, value|
            expect(entry.parsed_metadata.fetch(key)).to eq(value)
          end
        end
      end

      context 'when using ValkyrieObjectFactory' do
        ['Work', 'WorkResource'].each do |model_name|
          context "for #{model_name}" do
            let(:data) { { model: model_name, source_identifier: identifier, title: "If You Want to Go Far" } }

            before do
              allow(Bulkrax).to receive(:object_factory).and_return(Bulkrax::ValkyrieObjectFactory)
            end

            it { is_expected.to be_a(Bulkrax::CsvEntry) }

            it "parses metadata" do
              entry.build_metadata

              expect(entry.factory_class).to eq(model_name.constantize)
              {
                "title" => ["If You Want to Go Far"],
                "admin_set_id" => "admin_set/default",
                "source" => [identifier]
              }.each do |key, value|
                expect(entry.parsed_metadata.fetch(key)).to eq(value)
              end
            end
          end
        end
      end
    end

    context 'for parser_class_name: "Bulkrax::OaiDcParser"' do
      let(:parser_class_name) { "Bulkrax::OaiDcParser" }
      let(:options) do
        {
          parser_fields: {
            "metadata_prefix" => 'oai_fcrepo',
            "base_url" => "http://oai.samvera.org/OAI-script",
            "thumbnail_url" => ''
          }
        }
      end
      let(:data) do
        %(<?xml version="1.0" encoding="UTF-8"?>
        <OAI-PMH xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
          <responseDate>2023-02-01T20:41:11Z</responseDate>
          <request verb="GetRecord">#{options.fetch(:parser_fields).fetch('base_url')}?identifier=#{identifier}&amp;metadataPrefix=#{options.fetch(:parser_fields).fetch('metadata_prefix')}&amp;verb=GetRecord</request>
          <GetRecord>
            <record>
              <header>
                <identifier>#{identifier}</identifier>
                <datestamp>2022-12-15T05:09:20Z</datestamp>
                <setSpec>adl:book</setSpec>
              </header>
              <metadata>
                <oai_fcrepo>
                  <title>If You Want to Go Far</title>
                  <resource_type>Article</resource_type>
                 </oai_fcrepo>
               </metadata>
            </record>
          </GetRecord>
        </OAI-PMH>)
      end

      it { is_expected.to be_a(Bulkrax::OaiDcEntry) }

      it "parses metadata" do
        allow(Bulkrax.object_factory).to receive(:search_by_property).and_return(nil)
        entry.build_metadata

        expect(entry.factory_class).to eq(Work)
        {
          "title" => ["If You Want to Go Far"],
          "admin_set_id" => "admin_set/default",
          "source" => [identifier]
        }.each do |key, value|
          expect(entry.parsed_metadata.fetch(key)).to eq(value)
        end
      end
    end

    context 'for parser_class_name: "Bulkrax::XmlParser"' do
      let(:parser_class_name) { "Bulkrax::XmlParser" }
      let(:data) do
        %(<metadata>
           <title>If You Want to Go Far</title>
           <resource_type>Article</resource_type>
         </record>)
      end

      it { is_expected.to be_a(Bulkrax::XmlEntry) }

      around do |spec|
        # Because of the implementation of XML parsing, we don't have defaults.  We set them here
        initial_value = Bulkrax.field_mappings[parser_class_name]
        Bulkrax.field_mappings[parser_class_name] = {
          'title' => { from: ['title'] },
          'single_object' => { from: ['resource_type'] },
          'source' => { from: ['identifier'], source_identifier: true }
        }
        spec.run
        Bulkrax.field_mappings[parser_class_name] = initial_value
      end

      it "parses metadata" do
        entry.build_metadata

        expect(entry.factory_class).to eq(Work)
        {
          "title" => ["If You Want to Go Far"],
          "admin_set_id" => "admin_set/default",
          "single_object" => "Article",
          "source" => [identifier]
        }.each do |key, value|
          expect(entry.parsed_metadata.fetch(key)).to eq(value)
        end
      end
    end
  end
end
