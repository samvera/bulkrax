# frozen_string_literal: true

require 'rails_helper'
require 'bulkrax/entry_spec_helper'

RSpec.describe Bulkrax::ParserExportRecordSet::Base, '#permission_filters' do
  let(:user) { instance_double(User, id: 1, user_key: 'user@example.com') }
  let(:admin_user) { instance_double(User, id: 2, user_key: 'admin@example.com') }
  let(:exporter) { Bulkrax::EntrySpecHelper.exporter_for(parser_class_name: "Bulkrax::CsvParser") }
  let(:parser) { exporter.parser }
  let(:record_set) { Bulkrax::ParserExportRecordSet::All.new(parser: parser) }

  before { allow(exporter).to receive(:user).and_return(user) }

  describe '#permission_filters' do
    context 'when the exporting user is a regular user' do
      let(:fq_filters) { ['read_access_group_ssim:public OR access_filter'] }

      before do
        fake_ability = instance_double(Ability, can_admin_exporters?: false)
        fake_scope = instance_double(Bulkrax::ExportScope)
        fake_builder = instance_double(Bulkrax::ExportSearchBuilder, to_h: { fq: fq_filters })
        allow(Ability).to receive(:new).and_return(fake_ability)
        allow(Bulkrax::ExportScope).to receive(:new).and_return(fake_scope)
        allow(Bulkrax::ExportSearchBuilder).to receive(:new).with(fake_scope).and_return(fake_builder)
      end

      it 'returns fq clauses from ExportSearchBuilder' do
        expect(record_set.send(:permission_filters)).to eq(fq_filters)
      end

      it 'is memoized (builder is not re-instantiated)' do
        record_set.send(:permission_filters)
        record_set.send(:permission_filters)
        expect(Bulkrax::ExportSearchBuilder).to have_received(:new).once
      end
    end

    context 'when the exporting user can_admin_exporters?' do
      before do
        fake_ability = instance_double(Ability, can_admin_exporters?: true)
        allow(Ability).to receive(:new).and_return(fake_ability)
      end

      it 'returns an empty array (no permission scoping)' do
        expect(record_set.send(:permission_filters)).to eq([])
      end
    end

    context 'when exporter has no user (nil)' do
      before do
        allow(exporter).to receive(:user).and_return(nil)
        fallback_user = instance_double(User, id: 99, user_key: 'batch@example.com')
        allow(Bulkrax).to receive(:fallback_user_for_importer_exporter_processing).and_return(fallback_user)
        fake_ability = instance_double(Ability, can_admin_exporters?: true)
        allow(Ability).to receive(:new).with(fallback_user).and_return(fake_ability)
      end

      it 'falls back to Bulkrax.fallback_user_for_importer_exporter_processing' do
        expect(record_set.send(:permission_filters)).to eq([])
      end
    end
  end

  describe 'query_kwargs with permission filters' do
    let(:fq_filters) { ['read_access_group_ssim:public'] }

    before { allow(record_set).to receive(:permission_filters).and_return(fq_filters) }

    it 'includes permission filters in fq' do
      expect(record_set.send(:query_kwargs)[:fq]).to eq(fq_filters)
    end
  end

  describe '#file_sets includes permission filters' do
    let(:fq_filters) { ['read_access_group_ssim:public'] }

    before do
      allow(record_set).to receive(:permission_filters).and_return(fq_filters)
      allow(record_set).to receive(:candidate_file_set_ids).and_return(['id1'])
      allow(Bulkrax.object_factory).to receive(:query).and_return([])
    end

    it 'passes fq to object_factory.query' do
      record_set.send(:file_sets)
      expect(Bulkrax.object_factory).to have_received(:query).with(anything, hash_including(fq: fq_filters))
    end
  end
end

RSpec.describe Bulkrax::ParserExportRecordSet::Importer, 'additive fq merge' do
  let(:exporter) { Bulkrax::EntrySpecHelper.exporter_for(parser_class_name: "Bulkrax::CsvParser") }
  let(:parser) { exporter.parser }
  let(:record_set) { described_class.new(parser: parser) }
  let(:user) { instance_double(User, id: 1, user_key: 'user@example.com') }
  let(:fq_filters) { ['read_access_group_ssim:public'] }

  before do
    allow(exporter).to receive(:user).and_return(user)
    allow(record_set).to receive(:permission_filters).and_return(fq_filters)
    allow(record_set).to receive(:complete_entry_identifiers).and_return(['id1'])
    allow(record_set).to receive(:solr_name).and_return('identifier_tesim')
    allow(Bulkrax.object_factory).to receive(:query).and_return([])
  end

  describe '#works merges fq additively' do
    it 'includes permission filters AND work-specific filters in fq' do
      record_set.send(:works)
      expect(Bulkrax.object_factory).to have_received(:query).with(
        anything,
        hash_including(fq: array_including('read_access_group_ssim:public'))
      )
    end
  end

  describe '#collections merges fq additively' do
    it 'includes permission filters AND collection-specific filters in fq' do
      record_set.send(:collections)
      expect(Bulkrax.object_factory).to have_received(:query).with(
        anything,
        hash_including(fq: array_including('read_access_group_ssim:public'))
      )
    end
  end

  describe '#file_sets merges fq additively' do
    it 'includes permission filters AND file-set-specific filters in fq' do
      record_set.send(:file_sets)
      expect(Bulkrax.object_factory).to have_received(:query).with(
        anything,
        hash_including(fq: array_including('read_access_group_ssim:public'))
      )
    end
  end
end
