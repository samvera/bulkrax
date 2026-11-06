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
      it { is_expected.to respond_to(:cached_schema_for) }
      it { is_expected.to respond_to(:search_by_property) }
      it { is_expected.to respond_to(:transactions) }
      it { is_expected.to respond_to(:solr_name) }
      it { is_expected.to respond_to(:publish) }
      it { is_expected.to respond_to(:query) }
    end

    describe '.cached_schema_for' do
      let(:field) { double('Field', name: :title) }
      let(:test_klass) do
        schema_fields = [field]
        klass = Class.new do
          def self.name
            'TestWork'
          end

          def self.schema
            nil
          end
        end
        klass.define_singleton_method(:schema) { schema_fields }
        klass
      end

      before do
        # rubocop:disable Lint/UnusedBlockArgument
        Hyrax.define_singleton_method(:schema_for) { |klass:, admin_set_id: nil| klass.new.singleton_class.schema || klass.schema } unless Hyrax.respond_to?(:schema_for)
        # rubocop:enable Lint/UnusedBlockArgument
      end

      it 'returns the schema without admin_set_id' do
        expect(described_class.cached_schema_for(klass: test_klass)).to eq([field])
      end

      it 'delegates to Hyrax.schema_for when admin_set_id is present' do
        schema = double('schema')
        allow(Hyrax).to receive(:schema_for).with(klass: test_klass, admin_set_id: 'set-1').and_return(schema)
        expect(described_class.cached_schema_for(klass: test_klass, admin_set_id: 'set-1')).to eq(schema)
      end

      it 'memoizes the result and only calls Hyrax.schema_for once per (klass, admin_set_id)' do
        schema = double('schema')
        allow(Hyrax).to receive(:schema_for).with(klass: test_klass, admin_set_id: 'set-memo').and_return(schema)
        described_class.cached_schema_for(klass: test_klass, admin_set_id: 'set-memo')
        described_class.cached_schema_for(klass: test_klass, admin_set_id: 'set-memo')
        expect(Hyrax).to have_received(:schema_for).once
      end

      it 'resolves the schema again in a later request or job' do
        old_schema = double('old schema')
        new_schema = double('new schema')
        allow(Hyrax).to receive(:schema_for).with(klass: test_klass, admin_set_id: 'set-exec').and_return(old_schema, new_schema)
        schemas = Array.new(2) do
          Rails.application.executor.wrap { described_class.cached_schema_for(klass: test_klass, admin_set_id: 'set-exec') }
        end
        expect(schemas).to eq([old_schema, new_schema])
      end

      it 'resolves the schema separately for each admin set' do
        schema_a = double('admin set A schema')
        schema_b = double('admin set B schema')
        allow(Hyrax).to receive(:schema_for).with(klass: test_klass, admin_set_id: 'set-a').and_return(schema_a)
        allow(Hyrax).to receive(:schema_for).with(klass: test_klass, admin_set_id: 'set-b').and_return(schema_b)
        schemas = %w[set-a set-b].map { |id| described_class.cached_schema_for(klass: test_klass, admin_set_id: id) }
        expect(schemas).to eq([schema_a, schema_b])
      end

      context 'when the tenant changes within one request or job' do
        let(:tenant) { Struct.new(:current).new('tenant-a') }

        before { stub_const('Apartment::Tenant', tenant) }

        it 'resolves the schema separately for each tenant' do
          schema_a = double('tenant A schema')
          schema_b = double('tenant B schema')
          allow(Hyrax).to receive(:schema_for).with(klass: test_klass, admin_set_id: 'admin_set/default').and_return(schema_a, schema_b)
          first = described_class.cached_schema_for(klass: test_klass, admin_set_id: 'admin_set/default')
          tenant.current = 'tenant-b'
          second = described_class.cached_schema_for(klass: test_klass, admin_set_id: 'admin_set/default')
          expect([first, second]).to eq([schema_a, schema_b])
        end
      end
    end

    describe '.schema_properties' do
      let(:field) { double('Field', name: :title) }
      let(:test_klass) do
        schema_fields = [field]
        klass = Class.new do
          def self.name
            'PropWork'
          end
        end
        klass.define_singleton_method(:schema) { schema_fields }
        klass
      end

      before do
        # rubocop:disable Lint/UnusedBlockArgument
        Hyrax.define_singleton_method(:schema_for) { |klass:, admin_set_id: nil| klass.new.singleton_class.schema || klass.schema } unless Hyrax.respond_to?(:schema_for)
        # rubocop:enable Lint/UnusedBlockArgument
      end

      it 'returns field names from the schema' do
        expect(described_class.schema_properties(klass: test_klass)).to eq(['title'])
      end

      it 'builds the field names once per request or job' do
        allow(field).to receive(:name).and_return(:title)
        2.times { described_class.schema_properties(klass: test_klass) }
        expect(field).to have_received(:name).once
      end

      it 'returns field names that callers cannot mutate for later lookups' do
        expect(described_class.schema_properties(klass: test_klass)).to be_frozen
      end

      it 'includes context-specific fields when admin_set_id is provided' do
        context_field = double('Field', name: :dimensions)
        schema = double('schema')
        allow(schema).to receive(:map) { |&block| [field, context_field].map(&block) }
        allow(Hyrax).to receive(:schema_for).with(klass: test_klass, admin_set_id: 'set-ctx').and_return(schema)
        result = described_class.schema_properties(klass: test_klass, admin_set_id: 'set-ctx')
        expect(result).to include('title', 'dimensions')
      end
    end

    describe '#permitted_attributes' do
      let(:test_klass) do
        fields = [double('Field', name: :title), double('Field', name: :id)]
        Class.new do
          define_singleton_method(:name) { 'PermittedWork' }
          define_singleton_method(:schema) { fields }
        end
      end
      let(:factory) do
        described_class.new(attributes: {},
                            source_identifier_value: 123,
                            work_identifier: 'title',
                            work_identifier_search_field: 'title_sim',
                            klass: test_klass)
      end

      it 'returns schema properties as symbols without duplicating base attributes' do
        expect(factory.send(:permitted_attributes)).to include(:title).and(all(be_a(Symbol)))
        expect(factory.send(:permitted_attributes).count(:id)).to eq(1)
      end
    end

    describe '#find' do
      let(:factory) do
        described_class.new(attributes: { id: id },
                            source_identifier_value: 'src-1',
                            work_identifier: :source,
                            work_identifier_search_field: 'bulkrax_identifier_sim',
                            klass: ImageResource)
      end

      before do
        stub_const('ImageResource', Class.new)
        allow(described_class).to receive(:search_by_property).and_return(nil)
      end

      [nil, ''].each do |blank_id|
        context "when the id is #{blank_id.inspect}" do
          let(:id) { blank_id }

          it 'finds nothing without looking up the id' do
            expect(described_class).not_to receive(:find)
            expect(factory.find).to be_nil
          end

          it 'finds the record by its source identifier' do
            record = ImageResource.new
            allow(described_class).to receive(:search_by_property).and_return(record)
            expect(factory.find).to eq(record)
          end
        end
      end

      context 'when the id is present' do
        let(:id) { 'existing-id' }
        let(:record) { ImageResource.new }

        it 'returns the record with that id' do
          allow(described_class).to receive(:find).with('existing-id').and_return(record)
          expect(factory.find).to eq(record)
        end
      end
    end

    describe '#find when the record found is of another model' do
      let(:id) { nil }
      let(:factory) do
        described_class.new(attributes: { id: id },
                            source_identifier_value: 'src-1',
                            work_identifier: :source,
                            work_identifier_search_field: 'bulkrax_identifier_sim',
                            klass: ImageResource)
      end

      before do
        stub_const('ImageResource', Class.new)
        stub_const('Image', Class.new)
        stub_const('EtdResource', Class.new)
      end

      it 'raises instead of updating it' do
        allow(described_class).to receive(:search_by_property).and_return(EtdResource.new)
        expect { factory.find }.to raise_error(ObjectFactoryInterface::ModelMismatchError, /src-1.*EtdResource.*ImageResource/)
      end

      context 'when it was found by id' do
        let(:id) { 'existing-id' }

        it 'raises naming the id' do
          allow(described_class).to receive(:find).with('existing-id').and_return(EtdResource.new)
          expect { factory.find }.to raise_error(ObjectFactoryInterface::ModelMismatchError, /existing-id.*EtdResource/)
        end
      end

      it 'checks the record a subclass override of #find_by_id returns' do
        subclass = Class.new(described_class) do
          def find_by_id
            EtdResource.new
          end
        end
        factory = subclass.new(attributes: {}, source_identifier_value: 'src-1', work_identifier: :source,
                               work_identifier_search_field: 'bulkrax_identifier_sim', klass: ImageResource)
        expect { factory.find }.to raise_error(ObjectFactoryInterface::ModelMismatchError)
      end

      it "returns it when it is the row's model under its other name" do
        record = Image.new
        allow(described_class).to receive(:search_by_property).and_return(record)
        expect(factory.find).to eq(record)
      end
    end

    describe '#create_file_set' do
      include_context 'with the Valkyrie memory adapter'

      let(:user) { create(:user) }
      let(:work) { Hyrax.persister.save(resource: WorkResource.new(title: ['parent'], depositor: user.user_key)) }
      let(:fixture_path) { Bulkrax::Engine.root.join('spec', 'fixtures', 'removed.png').to_s }

      def build_factory(title, visibility: nil, files: 1, **row)
        attributes = { 'title' => [title], 'parents' => [work.id.to_s], 'file' => [fixture_path] * files, 'visibility' => visibility }.compact.merge(row)
        described_class.new(attributes: attributes, source_identifier_value: title, work_identifier: :bulkrax_identifier,
                            work_identifier_search_field: 'bulkrax_identifier_tesim', related_parents_parsed_mapping: 'parents',
                            user: user, klass: Hyrax::FileSet).tap do |factory|
          allow(factory).to receive(:find_record) { [nil, reloaded(work)] }
        end
      end

      def create_file_set(title = 'first', upload = uploaded_file, visibility: nil)
        build_factory(title, visibility: visibility).send(:create_file_set, uploaded_files: [upload.id])
      end

      def uploaded_file
        Hyrax::UploadedFile.create(file: File.open(fixture_path), user: user)
      end

      def reloaded(resource)
        Hyrax.query_service.find_by(id: resource.id)
      end

      def save_work_with(embargo: nil, lease: nil)
        work.embargo = Hyrax.persister.save(resource: embargo) if embargo
        work.lease = Hyrax.persister.save(resource: lease) if lease
        Hyrax::EmbargoManager.apply_embargo_for(resource: work)
        Hyrax::LeaseManager.apply_lease_for(resource: work)
        work.permission_manager.acl.save
        Hyrax.persister.save(resource: work)
      end

      let(:embargo) do
        Hyrax::Embargo.new(embargo_release_date: 1.month.from_now.to_date, visibility_during_embargo: 'restricted', visibility_after_embargo: 'open')
      end

      it 'creates the file set and leaves the work untouched' do
        file_set = create_file_set

        expect(file_set).to be_a(Hyrax::FileSet).and(be_persisted)
        expect(file_set.title).to eq ['first']
        expect(reloaded(work).member_ids).to be_empty
      end

      it 'leaves the ingest for the relationship pass' do
        expect { create_file_set }.not_to have_enqueued_job(ValkyrieIngestJob)
      end

      it "gives the file set the work's permissions" do
        work.permission_manager.edit_groups = ['editors']
        work.permission_manager.acl.save

        expect(reloaded(create_file_set).edit_groups).to include('editors')
      end

      it 'creates file sets for one work, at once, without saving the work' do
        uploads = Array.new(3) { uploaded_file }
        factories = %w[first second third].map { |title| build_factory(title) }

        factories.zip(uploads).map { |factory, upload| Thread.new { factory.send(:create_file_set, uploaded_files: [upload.id]) } }.each(&:join)

        expect(reloaded(work).member_ids).to be_empty
        expect(uploads.map { |upload| upload.reload.file_set_uri }).to all(be_present)
      end

      context 'with a visibility on the row' do
        it "gives the file set that visibility rather than the work's" do
          file_set = create_file_set(visibility: 'open')

          expect(reloaded(work).visibility).to eq 'restricted'
          expect(reloaded(file_set).visibility).to eq 'open'
        end

        it "does not copy down the work's embargo" do
          save_work_with(embargo: embargo)
          file_set = reloaded(create_file_set(visibility: 'open'))

          expect(file_set.embargo).to be_nil
          expect(file_set.visibility).to eq 'open'
        end
      end

      context 'without a visibility on the row' do
        it "stays restricted under an open work until it is attached" do
          work.visibility = 'open'
          work.permission_manager.acl.save

          expect(reloaded(create_file_set).visibility).to eq 'restricted'
        end

        it "takes none of the work's lease until it is attached" do
          save_work_with(lease: Hyrax::Lease.new(lease_expiration_date: 1.month.from_now.to_date, visibility_during_lease: 'open',
                                                 visibility_after_lease: 'restricted'))
          file_set = reloaded(create_file_set)

          expect(file_set.lease).to be_nil
          expect(file_set.visibility).to eq 'restricted'
        end

        it "stays restricted for an embargo visibility, which only the work can carry" do
          save_work_with(embargo: embargo)
          file_set = reloaded(create_file_set(visibility: 'embargo'))

          expect(file_set.embargo).to be_nil
          expect(file_set.visibility).to eq 'restricted'
        end
      end

      it 'fails a row with more than one file without creating anything' do
        expect { build_factory('first', files: 2).send(:create_file_set, uploaded_files: [uploaded_file.id, uploaded_file.id]) }
          .to raise_error(StandardError, 'first lists 2 files; a file set row takes one')
        expect(Hyrax.query_service.find_all_of_model(model: Hyrax::FileSet).to_a).to be_empty
      end

      it 'fails a row whose parent is not a work without creating anything' do
        upload = uploaded_file
        collection = Hyrax.persister.save(resource: Hyrax::PcdmCollection.new(title: ['collection']))
        factory = build_factory('first')
        allow(factory).to receive(:find_record).and_return([nil, collection])

        expect { factory.send(:create_file_set, uploaded_files: [upload.id]) }
          .to raise_error(StandardError, "first names parent #{work.id}, which is a Hyrax::PcdmCollection, not a work")
        expect(Hyrax.query_service.find_all_of_model(model: Hyrax::FileSet).to_a).to be_empty
        expect(upload.reload.file_set_uri).to be_nil
      end

      it 'fails a row whose parent is not found without creating anything' do
        upload = uploaded_file
        factory = build_factory('first')
        allow(factory).to receive(:find_record).and_return([nil, nil])

        expect { factory.send(:create_file_set, uploaded_files: [upload.id]) }
          .to raise_error(StandardError, "first names parent #{work.id}, which was not found")
        expect(Hyrax.query_service.find_all_of_model(model: Hyrax::FileSet).to_a).to be_empty
        expect(upload.reload.file_set_uri).to be_nil
      end

      context 'when a re-import updates the file set after its work changed visibility' do
        let(:file_set) { reloaded(create_file_set(visibility: 'open')) }

        def reimport(visibility: nil, **row)
          build_factory('first', visibility: visibility, **row).tap do |factory|
            allow(factory).to receive(:object).and_return(file_set)
            allow(factory).to receive(:perform_transaction_for) { reloaded(file_set) }
          end
        end

        def update_file_set(visibility: nil)
          reloaded(reimport(visibility: visibility).send(:update_file_set, {}))
        end

        before { Hyrax.persister.save(resource: work.tap { |w| w.member_ids = [file_set.id] }) }

        it "takes the work's visibility when the row has none" do
          work.visibility = 'authenticated'
          work.permission_manager.acl.save

          expect(update_file_set.visibility).to eq 'authenticated'
        end

        it "takes the work's embargo when the row has no visibility" do
          save_work_with(embargo: embargo)
          updated = update_file_set

          expect(updated.visibility).to eq 'restricted'
          expect(updated.embargo).to be_present
        end

        it "keeps the row's visibility" do
          save_work_with(embargo: embargo)

          expect(update_file_set(visibility: 'open').visibility).to eq 'open'
        end

        it "passes the row's embargo to the file set form, which sets it" do
          release_date = 1.month.from_now.to_date.to_s
          row = { 'embargo_release_date' => release_date, 'visibility_during_embargo' => 'restricted', 'visibility_after_embargo' => 'open' }
          factory = reimport(visibility: 'embargo', **row)
          factory.send(:update_file_set, {})

          expect(factory).to have_received(:perform_transaction_for)
            .with(object: anything, attrs: hash_including(visibility: 'embargo', embargo_release_date: release_date))
        end

        it "reindexes the file set with the work's embargo" do
          save_work_with(embargo: embargo)
          allow(Hyrax.index_adapter).to receive(:save)

          update_file_set

          expect(Hyrax.index_adapter).to have_received(:save)
            .with(resource: having_attributes(embargo: having_attributes(embargo_release_date: embargo.embargo_release_date)))
        end

        it 'clears its ended embargo, so the expiry job cannot release it to open later' do
          file_set.embargo = Hyrax.persister.save(resource: Hyrax::Embargo.new(embargo_release_date: 1.day.ago.to_date,
                                                                               visibility_during_embargo: 'restricted',
                                                                               visibility_after_embargo: 'open'))
          Hyrax.persister.save(resource: file_set)

          updated = update_file_set
          Hyrax::EmbargoManager.release_embargo_for(resource: updated)

          expect(updated.visibility).to eq 'restricted'
          expect(updated.embargo.embargo_release_date).to be_nil
        end

        it 'clears an ended embargo embedded without an id, as on Hyrax 4, without saving it as a record of its own' do
          ended = Hyrax::Embargo.new(embargo_release_date: 1.day.ago.to_date, visibility_during_embargo: 'restricted', visibility_after_embargo: 'open')
          file_set.embargo = ended

          expect { described_class.send(:clear_ended_embargo_and_lease, file_set) }
            .not_to(change { Hyrax.query_service.find_all_of_model(model: Hyrax::Embargo).count })
          expect(ended.embargo_release_date).to be_nil
        end

        it 'leaves an unattached file set to take its visibility when it is attached' do
          Hyrax.persister.save(resource: work.tap { |w| w.member_ids = [] })
          work.visibility = 'authenticated'
          work.permission_manager.acl.save

          expect(update_file_set.visibility).to eq 'open'
        end

        context 'when the row names another work' do
          let(:other_work) { Hyrax.persister.save(resource: WorkResource.new(title: ['other'])) }

          it 'fails the row without touching the file set, which stays in its work only' do
            factory = reimport
            allow(factory).to receive(:find_record) { [nil, reloaded(other_work)] }

            expect { factory.send(:update_file_set, {}) }
              .to raise_error(StandardError, "first is already in work #{work.id}; moving a file set to #{other_work.id} is not supported")
            expect(factory).not_to have_received(:perform_transaction_for)
            expect(Hyrax.query_service.find_parents(resource: file_set).map(&:id)).to eq [work.id]
          end

          it 'updates the file set when the row names its own work' do
            factory = reimport
            factory.send(:update_file_set, {})

            expect(factory).to have_received(:perform_transaction_for)
          end
        end

        it 'keeps the file set restricted while its own embargo lasts' do
          work.visibility = 'open'
          work.permission_manager.acl.save
          file_set.embargo = Hyrax.persister.save(resource: embargo)
          Hyrax::EmbargoManager.apply_embargo_for(resource: file_set)
          file_set.permission_manager.acl.save
          Hyrax.persister.save(resource: file_set)

          expect(update_file_set.visibility).to eq 'restricted'
        end
      end

      it 'fails a row whose file is already attached' do
        upload = uploaded_file
        upload.update!(file_set_uri: 'already-attached')

        expect { create_file_set('first', upload) }.to raise_error(StandardError, 'first has no file to attach')
      end
    end

    describe '.add_child_to_parent_work' do
      include_context 'with the Valkyrie memory adapter'

      let(:work) { Hyrax.persister.save(resource: WorkResource.new(title: ['parent'])) }
      let(:file_set) { Hyrax.persister.save(resource: Hyrax::FileSet.new(title: ['first'])) }
      let(:other_file_set) { Hyrax.persister.save(resource: Hyrax::FileSet.new(title: ['other'])) }

      it 'makes the first file set added the representative and thumbnail, as Hyrax does on attach' do
        described_class.add_child_to_parent_work(parent: work, child: file_set)
        parent = described_class.add_child_to_parent_work(parent: work, child: other_file_set)

        expect(parent).to have_attributes(member_ids: [file_set.id, other_file_set.id], representative_id: file_set.id, thumbnail_id: file_set.id)
      end

      it 'keeps a representative the work already has' do
        work.representative_id = other_file_set.id
        parent = described_class.add_child_to_parent_work(parent: Hyrax.persister.save(resource: work), child: file_set)

        expect(parent).to have_attributes(representative_id: other_file_set.id, thumbnail_id: file_set.id)
      end

      it 'returns the work as saved, not the copy passed in, when the child is already a member' do
        stale = work
        saved = Hyrax.persister.save(resource: work.tap { |w| w.member_ids = [file_set.id, other_file_set.id] })

        expect(described_class.add_child_to_parent_work(parent: stale, child: file_set).member_ids).to eq saved.member_ids
      end
    end

    describe '.uploads_awaiting_ingest' do
      include_context 'with the Valkyrie memory adapter'

      let(:user) { create(:user) }
      let(:file_set) { Hyrax.persister.save(resource: Hyrax::FileSet.new(title: ['first'])) }
      let!(:upload) do
        Hyrax::UploadedFile.create!(file: File.open(Bulkrax::Engine.root.join('spec', 'fixtures', 'removed.png')), user: user, file_set_uri: file_set.id.to_s)
      end

      it 'returns the uploads of a file set with no file yet' do
        expect(described_class.uploads_awaiting_ingest(resource: file_set)).to eq [upload]
      end

      it 'returns none for a file set that has its file' do
        file_set.file_ids = [Valkyrie::ID.new('ingested-file')]

        expect(described_class.uploads_awaiting_ingest(resource: file_set)).to be_empty
      end

      it 'returns none for a work' do
        work = Hyrax.persister.save(resource: WorkResource.new(title: ['parent']))

        expect(described_class.uploads_awaiting_ingest(resource: work)).to be_empty
      end
    end

    describe '.ingest_later' do
      let(:upload) { instance_double(Hyrax::UploadedFile, id: 7) }

      it 'queues the ingest' do
        allow(ValkyrieIngestJob).to receive(:perform_later).with(upload).and_return(true)

        described_class.ingest_later(upload: upload)

        expect(ValkyrieIngestJob).to have_received(:perform_later).with(upload)
      end

      it 'raises when the enqueue is aborted without raising' do
        allow(ValkyrieIngestJob).to receive(:perform_later).and_return(false)

        expect { described_class.ingest_later(upload: upload) }.to raise_error('Could not queue the ingest of upload 7')
      end
    end

    describe '#update_file_set' do
      let(:orig_file_set) do
        double(FileSet, bulkrax_identifier: 'fs-123', title: ["Custom File Set Title"], id: 'some-long-identifier')
      end
      let(:valkyrie_object_factory) do
        described_class.new(
          attributes: {},
          source_identifier_value: 'fs-123',
          work_identifier: :bulkrax_identifier,
          work_identifier_search_field: "bulkrax_identifier_tesim",
          related_parents_parsed_mapping: "parents",
          importer_run_id: importer_run.id
        )
      end
      let(:importer_run) { FactoryBot.create(:bulkrax_importer_run) }
      before do
        stub_request(:head, %r{http://localhost:8986/rest/test.*}).to_return(status: 200, body: "", headers: {})
        stub_request(:get, %r{http://localhost:8986/rest/test.*}).to_return(status: 200, body: "", headers: {})
      end
      it 'creates transactions for the file_set object' do
        allow(valkyrie_object_factory).to receive(:object).and_return(orig_file_set)
        expect(valkyrie_object_factory).to receive(:perform_transaction_for).with(object: satisfy { |data| data.id == 'some-long-identifier' }, attrs: {}).once

        valkyrie_object_factory.send(:update_file_set, {})
      end

      context 'with a remote file' do
        let(:remote_file) { { url: 'https://example.com/new.jpg', file_name: 'new.jpg' } }
        let(:path) { Rails.root.join('tmp', 'new.jpg').to_s }
        let(:use) { ::Valkyrie::Vocab::PCDMUse }
        let(:previous) { double('FileMetadata', id: 'old-original', checksum: ['0' * 32], file_identifier: 'disk://old.jpg', pcdm_use: [use.OriginalFile]) }
        let(:thumbnail) { double('FileMetadata', id: 'old-thumbnail', file_identifier: 'disk://thumbnail.jpeg', pcdm_use: [use.ThumbnailImage]) }
        let(:service_file) { double('FileMetadata', id: 'old-mp4', file_identifier: 'disk://old.mp4', pcdm_use: [use.ServiceFile]) }
        let(:transcript) { double('FileMetadata', id: 'transcript', file_identifier: 'disk://transcript.txt', pcdm_use: [use.Transcript]) }
        let(:new_original) { double('FileMetadata', id: 'new-original', file_identifier: 'disk://new.jpg') }
        let(:file_set) { double('FileSet', id: 'fs-id', original_file: previous, file_ids: %w[old-original old-thumbnail old-mp4 transcript]) }
        let(:uploaded) { double('FileSet', id: 'fs-id', file_ids: %w[old-original old-thumbnail old-mp4 transcript new-original]) }
        let(:custom_queries) { double('custom_queries') }
        let(:derivatives) { double('FileSetDerivativesService', cleanup_derivatives: true) }
        let(:destroy_transaction) { double('transaction') }
        let(:originals) { [previous, new_original] }

        before do
          File.write(path, 'new bytes')
          allow(valkyrie_object_factory).to receive(:object).and_return(orig_file_set)
          allow(valkyrie_object_factory).to receive(:perform_transaction_for).and_return(file_set)
          allow(valkyrie_object_factory).to receive(:download_file).with(remote_file[:url]).and_return(path)
          allow(valkyrie_object_factory).to receive(:transactions).and_return('file_metadata.destroy' => destroy_transaction)
          allow(Hyrax).to receive(:custom_queries).and_return(custom_queries)
          allow(custom_queries).to receive(:find_files).with(file_set: file_set).and_return([previous, thumbnail, service_file, transcript])
          allow(custom_queries).to receive(:find_files).with(file_set: uploaded).and_return([transcript, new_original])
          allow(custom_queries).to receive(:find_many_file_metadata_by_use) { originals }
          allow(Hyrax::FileSetDerivativesService).to receive(:new).with(file_set).and_return(derivatives)
          allow(Hyrax::ValkyrieUpload).to receive(:file)
          allow(Hyrax.query_service).to receive(:find_by).with(id: 'fs-id').and_return(uploaded)
          allow(uploaded).to receive(:file_ids=)
          allow(Hyrax.persister).to receive(:save).with(resource: uploaded).and_return(uploaded)
          allow(destroy_transaction).to receive(:call) { |file| Dry::Monads::Success(file) }
          allow(Hyrax.index_adapter).to receive(:save)
          allow(Hyrax.persister).to receive(:delete)
          allow(Hyrax.publisher).to receive(:publish)
        end

        after { FileUtils.rm_f(path) }

        it 'uploads the remote file as the new original' do
          valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file])

          expect(Hyrax::ValkyrieUpload).to have_received(:file).with(hash_including(filename: 'new.jpg', file_set: file_set))
        end

        it "clears the old file's derivatives before the upload" do
          valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file])

          expect(derivatives).to have_received(:cleanup_derivatives).ordered
          expect(Hyrax::ValkyrieUpload).to have_received(:file).ordered
        end

        it "fails a row whose download fails before saving the file set's metadata" do
          allow(valkyrie_object_factory).to receive(:download_file).and_raise('Failed to download file')

          expect { valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file]) }.to raise_error('Failed to download file')
          expect(valkyrie_object_factory).not_to have_received(:perform_transaction_for)
        end

        it 'detaches the old original and its derivative records, keeping the new original and other files' do
          valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file])

          expect(uploaded).to have_received(:file_ids=).with(%w[transcript new-original])
          expect(destroy_transaction).to have_received(:call).with(previous)
          expect(destroy_transaction).to have_received(:call).with(thumbnail)
          expect(destroy_transaction).to have_received(:call).with(service_file)
          expect(destroy_transaction).not_to have_received(:call).with(transcript)
          expect(Hyrax.index_adapter).to have_received(:save).with(resource: uploaded)
        end

        context 'when storage keeps the new file at the old path' do
          let(:new_original) { double('FileMetadata', id: 'new-original', file_identifier: 'disk://old.jpg') }

          it "deletes the old original's record but not the bytes, which are now the new file" do
            valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file])

            expect(destroy_transaction).not_to have_received(:call).with(previous)
            expect(Hyrax.persister).to have_received(:delete).with(resource: previous)
            expect(Hyrax.publisher).to have_received(:publish).with('file.metadata.deleted', metadata: previous)
          end
        end

        context 'when storage keeps versions' do
          let(:originals) { [previous] }

          it 'keeps the original, now holding the new version, and detaches its derivatives' do
            valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file])

            expect(uploaded).to have_received(:file_ids=).with(%w[old-original transcript new-original])
            expect(destroy_transaction).not_to have_received(:call).with(previous)
            expect(destroy_transaction).to have_received(:call).with(thumbnail)
          end
        end

        { 'MD5' => Digest::MD5, 'SHA1' => Digest::SHA1 }.each do |name, digest|
          it "leaves the file set alone when the remote file matches its original's #{name}" do
            allow(previous).to receive(:checksum).and_return([digest.hexdigest('new bytes')])

            expect(valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file])).to eq file_set
            expect(derivatives).not_to have_received(:cleanup_derivatives)
            expect(Hyrax::ValkyrieUpload).not_to have_received(:file)
          end
        end

        it 'fails a row with more than one remote file before changing anything' do
          expect { valkyrie_object_factory.send(:update_file_set, remote_files: [remote_file, remote_file]) }
            .to raise_error(StandardError, 'fs-123 lists 2 remote files; a file set takes one')
          expect(valkyrie_object_factory).not_to have_received(:perform_transaction_for)
        end
      end
    end

    describe 'FileFactoryInnerWorkings#new_remote_files' do
      let(:file_set) { Hyrax::FileSet.new }
      let(:object_factory) do
        instance_double(described_class, object: file_set, klass: Hyrax::FileSet, attributes: { remote_files: ['https://example.com/new.jpg', 'not a url'] })
      end

      before do
        allow(Bulkrax).to receive(:file_model_class).and_return(Hyrax::FileSet)
        allow(Bulkrax::Importer).to receive(:safe_uri_filename) { |url| File.basename(url) }
      end

      it "keeps a file set's valid remote files without comparing an import_url" do
        inner = described_class::FileFactoryInnerWorkings.new(object_factory: object_factory)

        expect(inner.new_remote_files.map { |file| file[:url] }).to eq ['https://example.com/new.jpg']
      end
    end

    describe '#destroy_existing_files' do
      let(:valkyrie_object_factory) do
        described_class.new(
          attributes: {},
          source_identifier_value: 'fs-123',
          work_identifier: :bulkrax_identifier,
          work_identifier_search_field: "bulkrax_identifier_tesim",
          related_parents_parsed_mapping: "parents",
          importer_run_id: importer_run.id
        )
      end
      let(:importer_run) { FactoryBot.create(:bulkrax_importer_run) }
      let(:object) { double('work', id: 'wk-1') }
      let(:custom_queries) { double('custom_queries') }

      before { allow(Hyrax).to receive(:custom_queries).and_return(custom_queries) }

      it 'handles a lazy enumerator of file sets without raising' do
        allow(custom_queries).to receive(:find_child_file_sets).with(resource: object).and_return([].lazy)

        expect { valkyrie_object_factory.send(:destroy_existing_files, object: object) }.not_to raise_error
      end

      context 'when the work has file sets' do
        let(:file_sets) { [double('file_set', id: 'fs-1'), double('file_set', id: 'fs-2')] }
        let(:other_member_id) { 'wk-child' }
        let(:object) do
          Struct.new(:id, :member_ids, :rendering_ids, :representative_id, :thumbnail_id)
                .new('wk-1', ['fs-1', other_member_id, 'fs-2'], ['fs-1'], 'fs-1', 'fs-1')
        end
        let(:destroy_transaction) { double('file_set.destroy') }
        let(:processing_log) { [] }

        before do
          loaded_file_sets = file_sets.lazy.map do |fs|
            processing_log << [:load, fs.id]
            fs
          end
          allow(custom_queries).to receive(:find_child_file_sets).with(resource: object).and_return(loaded_file_sets)
          allow(valkyrie_object_factory).to receive(:transactions).and_return('file_set.destroy' => destroy_transaction)
          allow(destroy_transaction).to receive(:with_step_args).and_return(destroy_transaction)
          allow(destroy_transaction).to receive(:call) do |fs|
            processing_log << [:destroy, fs.id]
            double('result', value!: fs)
          end
        end

        it 'loads each file set once and destroys it before loading the next' do
          valkyrie_object_factory.send(:destroy_existing_files, object: object)

          expect(processing_log).to eq([[:load, 'fs-1'], [:destroy, 'fs-1'], [:load, 'fs-2'], [:destroy, 'fs-2']])
        end

        it 'destroys each file set and removes them from the work' do
          valkyrie_object_factory.send(:destroy_existing_files, object: object)

          expect(destroy_transaction).to have_received(:call).with(file_sets[0])
          expect(destroy_transaction).to have_received(:call).with(file_sets[1])
          expect(object.member_ids).to eq([other_member_id])
          expect(object).to have_attributes(rendering_ids: [], representative_id: nil, thumbnail_id: nil)
        end
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
              our_mock = double(Object, { id: 123 })
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

  describe '#convert_based_near_to_attributes' do
    subject(:factory) { build(:valkyrie_object_factory) }

    context 'when based_near is absent' do
      it 'returns attrs unchanged' do
        attrs = { title: ['A Title'] }
        result = factory.send(:convert_based_near_to_attributes, attrs)
        expect(result).to eq(title: ['A Title'])
        expect(result).not_to have_key(:based_near_attributes)
      end
    end

    context 'when based_near is blank' do
      it 'removes based_near and returns attrs without based_near_attributes' do
        attrs = { based_near: [] }
        result = factory.send(:convert_based_near_to_attributes, attrs)
        expect(result).not_to have_key(:based_near)
        expect(result).not_to have_key(:based_near_attributes)
      end
    end

    context 'when based_near contains valid URIs' do
      let(:uri1) { 'http://sws.geonames.org/5128581/' }
      let(:uri2) { 'http://sws.geonames.org/4930956/' }

      it 'removes based_near and adds based_near_attributes' do
        attrs = { based_near: [uri1, uri2] }
        result = factory.send(:convert_based_near_to_attributes, attrs)
        expect(result).not_to have_key(:based_near)
        expect(result[:based_near_attributes]).to eq(
          '0' => { 'id' => uri1, '_destroy' => 'false' },
          '1' => { 'id' => uri2, '_destroy' => 'false' }
        )
      end

      it 'works with a single URI' do
        attrs = { based_near: [uri1] }
        result = factory.send(:convert_based_near_to_attributes, attrs)
        expect(result[:based_near_attributes]).to eq(
          '0' => { 'id' => uri1, '_destroy' => 'false' }
        )
      end
    end

    context 'when based_near contains invalid (non-URI) values' do
      it 'raises a StandardError with a helpful message' do
        attrs = { based_near: ['not-a-uri'] }
        expect { factory.send(:convert_based_near_to_attributes, attrs) }
          .to raise_error(StandardError, /Invalid value\(s\) for location \(based_near\).*not-a-uri/)
      end

      it 'raises even when mixed with valid URIs' do
        attrs = { based_near: ['http://sws.geonames.org/5128581/', 'plaintext'] }
        expect { factory.send(:convert_based_near_to_attributes, attrs) }
          .to raise_error(StandardError, /plaintext/)
      end
    end
  end
end
