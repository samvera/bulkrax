# frozen_string_literal: false

require 'rails_helper'

module Bulkrax
  # NOTE: Unable to put this file in spec/factories/bulkrax (where it would mirror the path in app/) because
  # (presumably) FactoryBot autoloads all files in spec/factories, which would always run this spec.
  # Why aren't there more tests?  In part because so much of the ObjectFactory require that we boot
  # up Fedora and SOLR; something that remains non-desirous due to speed.

  RSpec.describe ValkyrieObjectFactory do
    describe 'instance methods' do
      subject(:object_factory) { build(:valkyrie_object_factory) }

      it { is_expected.to respond_to(:create) }
      it { is_expected.to respond_to(:update) }
      it { is_expected.to respond_to(:delete) }
      it { is_expected.to respond_to(:run) }
      it { is_expected.to respond_to(:transactions) }
    end

    describe 'class methods' do
      subject(:object_factory) { ValkyrieObjectFactory }

      it { is_expected.to respond_to(:find) }
      it { is_expected.to respond_to(:find_or_create_default_admin_set) }
      it { is_expected.to respond_to(:save!) }
      it { is_expected.to respond_to(:update_index) }
      it { is_expected.to respond_to(:update_index_for_file_sets_of) }
      it { is_expected.to respond_to(:add_child_to_parent_work) }
      it { is_expected.to respond_to(:add_resource_to_collection) }
      it { is_expected.to respond_to(:file_sets_for) }
      it { is_expected.to respond_to(:ordered_file_sets_for) }
      it { is_expected.to respond_to(:model_name) }
      it { is_expected.to respond_to(:thumbnail_for) }
      it { is_expected.to respond_to(:filename_for) }
      it { is_expected.to respond_to(:original_file) }
      it { is_expected.to respond_to(:field_multi_value?) }
      it { is_expected.to respond_to(:field_supported?) }
      it { is_expected.to respond_to(:schema_properties) }
      it { is_expected.to respond_to(:search_by_property) }
      it { is_expected.to respond_to(:transactions) }
      it { is_expected.to respond_to(:solr_name) }
      it { is_expected.to respond_to(:publish) }
      it { is_expected.to respond_to(:query) }
    end

    describe '.search_by_property' do
      let(:active_fedora_relation) { ActiveFedora::Relation.new(ActiveFedora::Base) }
      let(:target_work) { FactoryBot.build(:avocado_work) }
      let(:other_work) { FactoryBot.build(:another_avocado_work) }

      around do |spec|
        class ::Avocado < Work
          property :bulkrax_identifier, predicate: ::RDF::URI("https://hykucommons.org/terms/bulkrax_identifier"), multiple: false
        end
        spec.run
        Object.send(:remove_const, :Avocado)
      end

      before do
        Hyrax.query_service.custom_queries.register_query_handler(Wings::CustomQueries::FindBySourceIdentifier)
        stub_request(:get, "http://localhost:8985/solr/hydra-test/select?fl=id&q=_query_:%22%7B!field%20f=bulkrax_identifier_tesim%7DTitle%22&qt=standard&rows=1000&sort=system_create_dtsi%20asc&start=0&wt=json")
          .to_return(status: 200, body: '{}', headers: {})
        allow(ActiveFedora::Base).to receive(:where).with({ "bulkrax_identifier_tesim" => "BU_Collegian-19481124" }).and_return(active_fedora_relation)
        allow(active_fedora_relation).to receive(:each).and_yield(target_work).and_yield(other_work)
      end

      it 'does find the collection with a partial match' do
        work = described_class.search_by_property(
          value: "BU_Collegian-19481124",
          search_field: "bulkrax_identifier_tesim",
          name_field: :bulkrax_identifier,
          klass: ActiveFedora::Base
        )
        expect(work.title).to eq(["A Work"])
        expect(ActiveFedora::Base).to have_received(:where).with({ "bulkrax_identifier_tesim" => "BU_Collegian-19481124" })
      end
    end
    describe '#create_file_set' do
      let(:valkyrie_object_factory) do
        described_class.new(
          attributes: { "bulkrax_identifier" => "fs-123",
                        "model" => "FileSet",
                        "file" => ["spec/fixtures/csv/files/moon.jpg"],
                        "parents" => ["gw-123"],
                        "title" => ["Custom File Set Title"],
                        "creator" => ["KKW"],
                        "rights_statement" => [""],
                        "visibility" => "restricted",
                        "admin_set_id" => "b75a49fb-e3d6-4ac7-b1c9-c527f7471508",
                        "uploaded_files" => [22] },
          source_identifier_value: 'fs-123', work_identifier: :bulkrax_identifier, work_identifier_search_field: "bulkrax_identifier_tesim",
          klass: Hyrax::FileSet, update_files: true, related_parents_parsed_mapping: "parents", importer_run_id: 123, user: FactoryBot.create(:user)
        )
      end
    #   let(:importer_run) { FactoryBot.create(:importer_run) }
      let(:custom_queries) do
        [
          Hyrax::CustomQueries::FindBySourceIdentifier,
          Hyrax::CustomQueries::FindAccessControl,
          Hyrax::CustomQueries::Navigators::FindFiles,
          Hyrax::CustomQueries::FindFileMetadata
        ]
      end
      let(:parent_work) { FactoryBot.build(:work, id: 'gw-123') }
    #   let(:resource_converter) do
    #     Valkyrie::Persistence::Postgres::ResourceConverter.new(
    #       parent_work,
    #       resource_factory: Valkyrie::Persistence::Postgres::ResourceFactory.new(
    #         adapter: Valkyrie::Persistence::Postgres::MetadataAdapter.new
    #       )
    #     )
    #   end
      around do |example|
        cached_file_model_class = Bulkrax.file_model_class
        Bulkrax.file_model_class = Hyrax::FileSet
        example.run
        Bulkrax.file_model_class = cached_file_model_class
      end
      before do
        Valkyrie::MetadataAdapter.register(Valkyrie::Persistence::Postgres::MetadataAdapter.new, :postgres_adapter)
        Valkyrie.config.metadata_adapter = :postgres_adapter
        custom_queries.each do |query|
          Hyrax.query_service.custom_queries.register_query_handler(query)
        end

        allow(Hyrax.query_service).to receive(:run_query).with("          SELECT * FROM orm_resources\n          WHERE metadata -> ? ->> 0 = ?\n          LIMIT 1;\n", :bulkrax_identifier, "fs-123").and_return([nil])
    #     stub_request(:get, "http://localhost:8985/solr/hydra-test/select?fl=id&q=_query_:%22%7B!field%20f=bulkrax_identifier_tesim%7Dfs-123%22&qt=standard&rows=1000&sort=system_create_dtsi%20asc&start=0&wt=json")
    #       .to_return(status: 200, body: '{}', headers: {})
    #     stub_request(:head, %r{http://localhost:8986/rest/test.*}).to_return(status: 200, body: "", headers: {})
    #     stub_request(:get, %r{http://localhost:8986/rest/test.*}).to_return(status: 200, body: "", headers: {})
        allow_any_instance_of(Bulkrax::DynamicRecordLookup).to receive(:find_record).with("gw-123", 123).and_return([parent_work])
    #     allow(Valkyrie::Persistence::Postgres::ResourceConverter).to receive(:new).with(parent_work, any_args).and_return(resource_converter)
    #     allow(resource_converter).to receive(:convert!).and_return("potato")
      end
      it "creates a FileSet" do
        valkyrie_object_factory.run!
      end
    end
    describe 'Hyrax-dependent methods' do
      context 'with Hyrax available' do
        describe '#solr_name' do
          it 'passes the method to Hyrax' do
            allow(Hyrax).to receive_message_chain(:config, :index_field_mapper, :solr_name).with('anything')
            described_class.solr_name('anything')
            expect(Hyrax.config.index_field_mapper).to have_received(:solr_name).with('anything')
          end
        end
        describe '#publish' do
          it 'passes the method to Hyrax' do
            publisher_double = double("Hyrax::Publisher")
            allow(Hyrax).to receive(:publisher).and_return(publisher_double)
            allow(publisher_double).to receive(:publish)
            described_class.publish(event: 'something')
            expect(Hyrax.publisher).to have_received(:publish).with("something", any_args)
          end
        end
        describe '#query' do
          it 'passes the method to Hyrax' do
            allow(Hyrax::SolrService).to receive(:query).with('anything', any_args)
            ValkyrieObjectFactory.query('anything')
            expect(Hyrax::SolrService).to have_received(:query).with('anything', any_args)
          end
        end
        describe '#save!' do
          context 'without a returned object' do
            it 'raises an error' do
              our_mock = double(Object, {id: 123})
              allow(Hyrax.persister).to receive(:save).with(resource: our_mock).and_return(nil)
              expect do
                described_class.save!(resource: our_mock, user: create(:user))
              end.to raise_error(Valkyrie::Persistence::ObjectNotFoundError)
            end
          end
        end
      end
      context 'with no Hyrax available' do
        around do |example|
          # Store original state
          had_constant = defined?(Hyrax)
          original_value = Hyrax if had_constant
          # Remove for test
          Object.send(:remove_const, :Hyrax) if had_constant
          example.run
          # Restore
          Object.const_set(:Hyrax, original_value) if had_constant
        end
        describe '#solr_name' do
          it 'raises an error' do
            expect do
              described_class.solr_name('anything')
            end.to raise_error(NotImplementedError)
          end
        end
        describe '#publish' do
          it 'raises an error' do
            expect do
              described_class.publish(event: 'anything')
            end.to raise_error(NotImplementedError)
          end
        end
        describe '#query' do
          it 'raises an error' do
            expect do
              described_class.query('anything')
            end.to raise_error(NotImplementedError)
          end
        end
        describe '#save!' do
          it 'just does a plain old save' do
            our_mock = double(Object)
            allow(our_mock).to receive(:save!)
            described_class.save!(resource: our_mock, user: create(:user))
            expect(our_mock).to have_received(:save!)
          end
        end
      end
    end
  end
end
