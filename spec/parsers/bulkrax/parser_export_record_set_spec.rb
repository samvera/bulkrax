# frozen_string_literal: true

require 'rails_helper'
require 'bulkrax/entry_spec_helper'

RSpec.describe Bulkrax::ParserExportRecordSet do
  describe '.for' do
    let(:parser) { Bulkrax::CsvParser.new(nil) }
    subject { described_class.for(parser: parser, export_from: export_from) }

    context 'export_from: "all"' do
      let(:export_from) { "all" }

      it { is_expected.to be_a described_class::All }
    end

    context 'export_from: "worktype"' do
      let(:export_from) { "worktype" }

      it { is_expected.to be_a described_class::Worktype }
    end

    context 'export_from: "collection"' do
      let(:export_from) { "collection" }

      it { is_expected.to be_a described_class::Collection }
    end

    context 'export_from: "importer"' do
      let(:export_from) { "importer" }

      it { is_expected.to be_a described_class::Importer }
    end

    context 'export_from: "undefined"' do
      let(:export_from) { "undefined" }

      it "raises a NameError exception" do
        expect { subject }.to raise_error(NameError)
      end
    end
  end
  describe '.in_batches' do
    it 'returns an empty array when given an empty array' do
      expect(described_class.in_batches([])).to eq([])
    end
    it 'yields multiple times based on the array size and page size' do
      expect { |block| described_class.in_batches([1, 2, 3, 4, 5], page_size: 2, &block) }.to yield_successive_args([1, 2], [3, 4], [5])
    end

    it 'returns an array based on the yielded block' do
      results = described_class.in_batches([1, 2, 3, 4, 5], page_size: 2) do |ids|
        ids.map { |id| "ID: #{id}" }
      end
      expect(results).to eq(["ID: 1", "ID: 2", "ID: 3", "ID: 4", "ID: 5"])
    end
  end
end

[Bulkrax::ParserExportRecordSet::All, Bulkrax::ParserExportRecordSet::Worktype, Bulkrax::ParserExportRecordSet::Collection].each do |klass|
  RSpec.describe klass do
    let(:works) do
      [
        SolrDocument.new(id: 1, member_ids_ssim: ["a", "b", "c"]),
        SolrDocument.new(id: 2, member_ids_ssim: ["d", "e", "f"])
      ]
    end

    let(:file_sets) do
      [
        SolrDocument.new(id: "a"),
        SolrDocument.new(id: "b"),
        SolrDocument.new(id: "c"),
        SolrDocument.new(id: "d"),
        SolrDocument.new(id: "e"),
        SolrDocument.new(id: "f")
      ]
    end

    let(:collections) do
      [
        SolrDocument.new(id: 100),
        SolrDocument.new(id: 200)
      ]
    end
    let(:exporter) { Bulkrax::EntrySpecHelper.exporter_for(parser_class_name: "Bulkrax::CsvParser", exporter_limit: limit) }
    let(:parser) { exporter.parser }

    let(:count_of_items) { 10 } # I hand calculated that based on the above

    let(:record_set) { described_class.new(parser: parser) }

    before do
      allow(record_set).to receive(:works).and_return(works)
      allow(record_set).to receive(:collections).and_return(collections)
      allow(record_set).to receive(:file_sets).and_return(file_sets)
    end

    describe '#count' do
      subject { record_set.count }

      context 'when the number of items exceed the provided a limit' do
        let(:limit) { 5 }
        it "will return the limit" do
          expect(subject).to eq(limit)
        end
      end

      context 'when the number of items is less than (or equal) to the provided limit' do
        let(:limit) { 100 }
        it 'will return the count of associated items' do
          expect(subject).to eq(count_of_items)
        end
      end

      context 'where there is no limit' do
        let(:limit) { nil }
        it 'will return the count of associated items' do
          expect(subject).to eq(count_of_items)
        end
      end
    end

    describe '#each' do
      context 'when the number of items exceed the provided a limit' do
        let(:limit) { 5 }
        it "will only yield as many times as the given limit" do
          expect do |block|
            record_set.each(&block)
          end.to yield_successive_args(
                   [works[0].id, parser.entry_class],
                   [works[1].id, parser.entry_class],
                   [collections[0].id, parser.collection_entry_class],
                   [collections[1].id, parser.collection_entry_class],
                   [works[0].fetch(Bulkrax.solr_key_for_member_file_ids).first, parser.file_set_entry_class]
                 )
        end
      end

      context 'when the number of items is less than (or equal) to the provided limit' do
        let(:limit) { 100 }
        it "will yield all of the associated items" do
          expect do |block|
            record_set.each(&block)
          end.to yield_successive_args(
                   [works[0].id, parser.entry_class],
                   [works[1].id, parser.entry_class],
                   [collections[0].id, parser.collection_entry_class],
                   [collections[1].id, parser.collection_entry_class],
                   [works[0].fetch(Bulkrax.solr_key_for_member_file_ids)[0], parser.file_set_entry_class],
                   [works[0].fetch(Bulkrax.solr_key_for_member_file_ids)[1], parser.file_set_entry_class],
                   [works[0].fetch(Bulkrax.solr_key_for_member_file_ids)[2], parser.file_set_entry_class],
                   [works[1].fetch(Bulkrax.solr_key_for_member_file_ids)[0], parser.file_set_entry_class],
                   [works[1].fetch(Bulkrax.solr_key_for_member_file_ids)[1], parser.file_set_entry_class],
                   [works[1].fetch(Bulkrax.solr_key_for_member_file_ids)[2], parser.file_set_entry_class]
                 )
        end
      end

      context "when there is no limit" do
        let(:limit) { nil }
        it "will yield all of the associcated items" do
          expect do |block|
            record_set.each(&block)
          end.to yield_successive_args(
                   [works[0].id, parser.entry_class],
                   [works[1].id, parser.entry_class],
                   [collections[0].id, parser.collection_entry_class],
                   [collections[1].id, parser.collection_entry_class],
                   [works[0].fetch(Bulkrax.solr_key_for_member_file_ids)[0], parser.file_set_entry_class],
                   [works[0].fetch(Bulkrax.solr_key_for_member_file_ids)[1], parser.file_set_entry_class],
                   [works[0].fetch(Bulkrax.solr_key_for_member_file_ids)[2], parser.file_set_entry_class],
                   [works[1].fetch(Bulkrax.solr_key_for_member_file_ids)[0], parser.file_set_entry_class],
                   [works[1].fetch(Bulkrax.solr_key_for_member_file_ids)[1], parser.file_set_entry_class],
                   [works[1].fetch(Bulkrax.solr_key_for_member_file_ids)[2], parser.file_set_entry_class]
                 )
        end
      end
    end
  end
end

RSpec.describe Bulkrax::ParserExportRecordSet::Importer do
  let(:file_sets) do
    [
      SolrDocument.new(id: "a"),
      SolrDocument.new(id: "b"),
      SolrDocument.new(id: "c"),
      SolrDocument.new(id: "d"),
      SolrDocument.new(id: "e"),
      SolrDocument.new(id: "f")
    ]
  end
  let(:works) do
    [
      SolrDocument.new(id: 1),
      SolrDocument.new(id: 2)
    ]
  end

  let(:collections) do
    [
      SolrDocument.new(id: 100),
      SolrDocument.new(id: 200)
    ]
  end
  let(:exporter) { Bulkrax::EntrySpecHelper.exporter_for(parser_class_name: "Bulkrax::CsvParser", exporter_limit: limit) }
  let(:parser) { exporter.parser }

  let(:count_of_items) { 10 } # I hand calculated that based on the above

  let(:record_set) { described_class.new(parser: parser) }

  before do
    allow(record_set).to receive(:works).and_return(works)
    allow(record_set).to receive(:collections).and_return(collections)
    allow(record_set).to receive(:file_sets).and_return(file_sets)
  end

  describe '#count' do
    subject { record_set.count }

    context 'when the number of items exceed the provided a limit' do
      let(:limit) { 5 }
      it "will return the limit" do
        expect(subject).to eq(limit)
      end
    end

    context 'when the number of items is less than (or equal) to the provided limit' do
      let(:limit) { 100 }
      it 'will return the count of associated items' do
        expect(subject).to eq(count_of_items)
      end
    end

    context 'where there is no limit' do
      let(:limit) { nil }
      it 'will return the count of associated items' do
        expect(subject).to eq(count_of_items)
      end
    end
  end

  describe '#each' do
    context 'when the number of items exceed the provided a limit' do
      let(:limit) { 5 }
      it "will only yield as many times as the given limit" do
        expect do |block|
          record_set.each(&block)
        end.to yield_successive_args(
                 [works[0].id, parser.entry_class],
                 [works[1].id, parser.entry_class],
                 [collections[0].id, parser.collection_entry_class],
                 [collections[1].id, parser.collection_entry_class],
                 [file_sets[0].id, parser.file_set_entry_class]
               )
      end
    end

    context 'when the number of items is less than (or equal) to the provided limit' do
      let(:limit) { 100 }
      it "will yield all of the associated items" do
        expect do |block|
          record_set.each(&block)
        end.to yield_successive_args(
                 [works[0].id, parser.entry_class],
                 [works[1].id, parser.entry_class],
                 [collections[0].id, parser.collection_entry_class],
                 [collections[1].id, parser.collection_entry_class],
                 [file_sets[0].id, parser.file_set_entry_class],
                 [file_sets[1].id, parser.file_set_entry_class],
                 [file_sets[2].id, parser.file_set_entry_class],
                 [file_sets[3].id, parser.file_set_entry_class],
                 [file_sets[4].id, parser.file_set_entry_class],
                 [file_sets[5].id, parser.file_set_entry_class]
               )
      end
    end

    context "when there is no limit" do
      let(:limit) { nil }
      it "will yield all of the associcated items" do
        expect do |block|
          record_set.each(&block)
        end.to yield_successive_args(
                 [works[0].id, parser.entry_class],
                 [works[1].id, parser.entry_class],
                 [collections[0].id, parser.collection_entry_class],
                 [collections[1].id, parser.collection_entry_class],
                 [file_sets[0].id, parser.file_set_entry_class],
                 [file_sets[1].id, parser.file_set_entry_class],
                 [file_sets[2].id, parser.file_set_entry_class],
                 [file_sets[3].id, parser.file_set_entry_class],
                 [file_sets[4].id, parser.file_set_entry_class],
                 [file_sets[5].id, parser.file_set_entry_class]
               )
      end
    end
  end
end
