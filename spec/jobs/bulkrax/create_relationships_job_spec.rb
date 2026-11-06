# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CreateRelationshipsJob, type: :job do
    let(:create_relationships_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
    let(:ability) { instance_double(Ability) }

    # create objects
    let(:collection1) { build(:collection, id: 'collection1_id') }
    let(:collection2) { build(:collection, id: 'collection2_id') }
    let(:work1) { build(:work, id: 'work1_id') }
    let(:work2) { build(:work, id: 'work1_id') }
    let(:updated_parent) { double('updated_parent') }

    # create entries
    let(:collection1_entry) { create(:bulkrax_csv_entry_collection, identifier: 'collection1_entry', importerexporter: importer) }
    let(:collection2_entry) { create(:bulkrax_csv_entry_collection, identifier: 'collection2_entry', importerexporter: importer) }
    let(:work1_entry) { create(:bulkrax_csv_entry_work, identifier: 'work1_entry', importerexporter: importer) }
    let(:work2_entry) { create(:bulkrax_csv_entry_work, identifier: 'work2_entry', importerexporter: importer) }

    before do
      allow(ImporterRun).to receive(:update_counters).and_return(true)
      allow(Ability).to receive(:new).and_return(ability)
      allow(ability).to receive(:authorize!).and_return(true)
      # The real work happens in the object factory. Each object factory
      # should have its own tests to verify that it does the right thing.
      allow(Bulkrax.object_factory).to receive(:add_resource_to_collection).and_return(true)
      allow(Bulkrax.object_factory).to receive(:update_index).and_return(true)
      allow(Bulkrax.object_factory).to receive(:publish).and_return(true)
      allow(create_relationships_job).to receive(:reschedule)
      allow(Bulkrax.object_factory).to receive(:add_child_to_parent_work).and_return(updated_parent)
      allow(Bulkrax.object_factory).to receive(:save!).and_return(true)
      allow(Bulkrax.object_factory).to receive(:find).with(collection1.id).and_return(collection1)
      allow(Bulkrax.object_factory).to receive(:find).with(collection2.id).and_return(collection2)
      allow(Bulkrax.object_factory).to receive(:find).with(work1.id).and_return(work1)
      allow(Bulkrax.object_factory).to receive(:find).with(work2.id).and_return(work2)
    end

    around do |spec|
      old = Bulkrax.object_factory
      Bulkrax.object_factory = Bulkrax::MockObjectFactory
      spec.run
      Bulkrax.object_factory = old
    end

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end

    describe '#perform' do
      subject(:perform) do
        create_relationships_job.perform(
          parent_identifier: parent_identifier, # source_identifier
          importer_run_id: importer.current_run.id
        )
      end

      context 'when adding a child work to a parent collection' do
        let(:pending_rel_test) do
          create(:pending_relationship,
                 importer_run_id: importer.current_run.id,
                 parent_id: parent_identifier,
                 child_id: work1_entry.identifier,
                 order: 1)
        end
        let(:parent_identifier) { collection1_entry.identifier }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([collection1_entry, collection1])
          allow(create_relationships_job).to receive(:find_record).with(work1_entry.identifier, importer.current_run.id).and_return([work1_entry, work1])
          pending_rel_test
        end

        it 'calls the object factory to assign the child work to the collection' do
          expect(Bulkrax.object_factory).to receive(:add_resource_to_collection).with(collection: collection1, resource: work1, user: importer.current_run.user)
          expect(Bulkrax.object_factory).to receive(:update_index).with(resources: [collection1])
          expect(Bulkrax.object_factory).to receive(:publish).with(event: 'object.membership.updated', object: collection1, user: importer.current_run.user)
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, processed_relationships: 1)
          perform
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end
      end

      context 'when adding a child collection to a parent collection' do
        let(:pending_rel_test) do
          create(:pending_relationship,
                 importer_run_id: importer.current_run.id,
                 parent_id: parent_identifier,
                 child_id: collection2_entry.identifier,
                 order: 1)
        end
        let(:parent_identifier) { collection1_entry.identifier }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([collection1_entry, collection1])
          allow(create_relationships_job).to receive(:find_record).with(collection2_entry.identifier, importer.current_run.id).and_return([collection2_entry, collection2])
          pending_rel_test
        end

        it 'calls the object factory to assign the child collection to the collection' do
          expect(Bulkrax.object_factory).to receive(:add_resource_to_collection).with(collection: collection1, resource: collection2, user: importer.current_run.user)
          expect(Bulkrax.object_factory).to receive(:update_index).with(resources: [collection1])
          expect(Bulkrax.object_factory).to receive(:publish).with(event: 'object.membership.updated', object: collection1, user: importer.current_run.user)
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, processed_relationships: 1)
          perform
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end
      end

      context 'when adding a child work to a parent work' do
        let(:pending_rel_test) do
          create(:pending_relationship,
                 importer_run_id: importer.current_run.id,
                 parent_id: parent_identifier,
                 child_id: work2_entry.identifier,
                 order: 1)
        end
        let(:parent_identifier) { work1_entry.identifier }
        let(:update_child_records_works_file_sets?) { false }
        let(:updated_parent) { work1 }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([work1_entry, work1])
          allow(create_relationships_job).to receive(:find_record).with(work2_entry.identifier, importer.current_run.id).and_return([work2_entry, work2])
          pending_rel_test
        end

        it 'calls the object factory to assign the child work to the parent_work' do
          expect(Bulkrax.object_factory).to receive(:add_child_to_parent_work).with(parent: work1, child: work2)
          expect(Bulkrax.object_factory).to receive(:update_index).with(resources: [work1])
          expect(Bulkrax.object_factory).not_to receive(:update_index_for_file_sets_of)
          expect(ImporterRun).to receive(:update_counters).with(importer.current_run.id, processed_relationships: 1)
          perform
        end

        it 'deletes the pending relationship' do
          expect { perform }.to change(Bulkrax::PendingRelationship, :count).by(-1)
        end

        it 'does not reschedule the job' do
          perform
          expect(create_relationships_job).not_to have_received(:reschedule)
        end
      end

      context 'when adding a child collection to a parent work' do
        let(:pending_rel_test) do
          create(:pending_relationship,
                 importer_run_id: importer.current_run.id,
                 parent_id: parent_identifier,
                 child_id: collection1_entry.identifier,
                 order: 1)
        end
        let(:parent_identifier) { work1_entry.identifier }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([work1_entry, work1])
          allow(create_relationships_job).to receive(:find_record).with(collection1_entry.identifier, importer.current_run.id).and_return([collection1_entry, collection1])
          pending_rel_test
        end

        it 'logs an error to the parent entry' do
          expect { perform }.to change(work1_entry, :failed?).to(true)
        end

        it 'does not count the failure while attempts remain' do
          expect(ImporterRun).not_to receive(:update_counters).with(importer.current_run.id, hash_including(:failed_relationships))
          perform
        end
      end

      context 'when adding a child record that is not found' do
        let(:pending_rel_test) do
          create(:pending_relationship,
                 importer_run_id: importer.current_run.id,
                 parent_id: parent_identifier,
                 child_id: child_id,
                 order: 1)
        end
        let(:parent_identifier) { collection1_entry.identifier }
        let(:child_id) { 'not_found' }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([work1_entry, work1])
          allow(create_relationships_job).to receive(:find_record).with(child_id, importer.current_run.id).and_return([nil, nil])
          pending_rel_test
        end

        it 'reschedules the job' do
          expect(ImporterRun).not_to receive(:update_counters).with(importer.current_run.id, hash_including(:failed_relationships))
          expect(create_relationships_job).to receive(:reschedule).with(parent_identifier: parent_identifier, importer_run_id: importer.current_run.id, run_user: importer.current_run.user, failure_count: 1)
          result = perform
          # Expect the result to be an array containing one RuntimeError
          expect(result).to match([an_instance_of(RuntimeError)])
        end
      end

      context 'when a child never resolves and the last attempt fails' do
        subject(:perform) do
          create_relationships_job.perform(
            parent_identifier: parent_identifier,
            importer_run_id: run.id,
            failure_count: described_class.max_failure_count - 1
          )
        end
        let(:run) { importer.current_run }
        let(:parent_identifier) { work1_entry.identifier }
        let!(:relationship) do
          create(:pending_relationship, importer_run_id: run.id, parent_id: parent_identifier, child_id: 'no-such-child', order: 1)
        end

        before do
          allow(ImporterRun).to receive(:update_counters).and_call_original
          allow(create_relationships_job).to receive(:find_record).and_call_original
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, run.id).and_return([work1_entry, work1])
          allow(Bulkrax.object_factory).to receive(:find).with('no-such-child')
                                                         .and_raise(Bulkrax::ObjectFactoryInterface::ObjectNotFoundError)
          importer.set_status_info('Complete', run)
        end

        it 'leaves no pending relationship' do
          perform
          expect(Bulkrax::PendingRelationship.pending.where(importer_run_id: run.id)).to be_empty
        end

        it 'names the missing child on the relationship and the parent entry' do
          perform
          expect(relationship.reload.status_message).to include('no-such-child')
          expect(work1_entry.reload.current_status.error_message).to include('no-such-child')
        end

        it 'counts the failed relationship once' do
          expect { perform }.to change { run.reload.failed_relationships }.by(1)
        end

        context 'when an earlier chain already failed a relationship for this parent' do
          before do
            earlier = create(:pending_relationship, importer_run_id: run.id, parent_id: parent_identifier, child_id: 'earlier-child', order: 2)
            earlier.update!(status_message: 'Child record earlier-child could not be found for parent work1_entry')
            run.update!(failed_relationships: 1)
            allow(Bulkrax.object_factory).to receive(:find).with('earlier-child')
                                                           .and_raise(Bulkrax::ObjectFactoryInterface::ObjectNotFoundError)
          end

          it 'counts each failed relationship once' do
            perform
            expect(run.reload.failed_relationships).to eq(2)
          end
        end

        it 'marks the importer as complete with failures' do
          perform
          expect(importer.reload.status).to eq('Complete (with failures)')
        end

        context 'when the importer has started a newer run' do
          let!(:newer_run) { importer.importer_runs.create! }

          before { importer.set_status_info('Complete', newer_run) }

          it 'leaves the newer run\'s status alone' do
            perform
            expect(Importer.find(importer.id).status).to eq('Complete')
          end
        end

        context 'when the identifiers are long' do
          let(:long_child) { "https://example.com/#{'c' * 230}" }
          let!(:relationship) do
            create(:pending_relationship, importer_run_id: run.id, parent_id: parent_identifier, child_id: long_child, order: 1)
          end

          before do
            allow(Bulkrax.object_factory).to receive(:find).with(long_child)
                                                           .and_raise(Bulkrax::ObjectFactoryInterface::ObjectNotFoundError)
          end

          it 'keeps the message within the column limit' do
            perform
            expect(relationship.reload.status_message.length).to be <= 255
          end
        end

        context 'when attempts remain' do
          subject(:perform) do
            create_relationships_job.perform(parent_identifier: parent_identifier, importer_run_id: run.id)
          end

          it 'does not count the failure yet' do
            expect { perform }.not_to change { run.reload.failed_relationships }
          end

          it 'leaves the relationship Pending' do
            perform
            expect(relationship.reload.status_message).to eq('Pending')
          end

          it 'leaves the importer complete' do
            perform
            expect(importer.reload.status).to eq('Complete')
          end
        end
      end

      shared_examples 'a failed relationship that links later' do
        let(:run) { importer.current_run }
        let!(:relationship) do
          create(:pending_relationship, importer_run_id: run.id, parent_id: parent_entry.identifier, child_id: child_entry.identifier, order: 1)
        end

        subject(:perform) { create_relationships_job.perform(parent_identifier: parent_entry.identifier, importer_run_id: run.id) }

        before do
          relationship.update!(status_message: "Child record #{child_entry.identifier} could not be found for parent #{parent_entry.identifier}")
          run.update!(failed_relationships: 1)
          importer.set_status_info('Complete (with failures)', run)
          allow(ImporterRun).to receive(:update_counters).and_call_original
          allow(create_relationships_job).to receive(:find_record).with(parent_entry.identifier, run.id).and_return([parent_entry, parent_record])
          allow(create_relationships_job).to receive(:find_record).with(child_entry.identifier, run.id).and_return([child_entry, child_record])
        end

        it 'no longer counts it as failed' do
          perform
          expect(run.reload.failed_relationships).to eq(0)
        end

        it 'marks the importer complete' do
          perform
          expect(Importer.find(importer.id).status).to eq('Complete')
        end

        context 'when another relationship for the parent still needs a retry' do
          before do
            create(:pending_relationship, importer_run_id: run.id, parent_id: parent_entry.identifier, child_id: 'not-yet-imported', order: 2)
            allow(create_relationships_job).to receive(:find_record).with('not-yet-imported', run.id).and_return([nil, nil])
          end

          it 'no longer counts the one that linked' do
            perform
            expect(run.reload.failed_relationships).to eq(0)
          end

          it 'marks the importer complete' do
            perform
            expect(Importer.find(importer.id).status).to eq('Complete')
          end
        end
      end

      context 'when an overlapping run of the job fails a relationship that this one then links' do
        let(:run) { importer.current_run }
        let(:parent_identifier) { work1_entry.identifier }
        let(:updated_parent) { work1 }
        let!(:relationship) do
          create(:pending_relationship, importer_run_id: run.id, parent_id: parent_identifier, child_id: work2_entry.identifier, order: 1)
        end

        subject(:perform) { create_relationships_job.perform(parent_identifier: parent_identifier, importer_run_id: run.id) }

        before do
          importer.set_status_info('Complete', run)
          allow(ImporterRun).to receive(:update_counters).and_call_original
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, run.id).and_return([work1_entry, work1])
          allow(create_relationships_job).to receive(:find_record).with(work2_entry.identifier, run.id).and_return([work2_entry, work2])
          allow(Bulkrax.object_factory).to receive(:add_child_to_parent_work) do
            Bulkrax::PendingRelationship.where(id: relationship.id).update_all(status_message: 'Child record work2_entry could not be found for parent work1_entry') # rubocop:disable Rails/SkipsModelValidations
            ImporterRun.where(id: run.id).update_all(failed_relationships: 1) # rubocop:disable Rails/SkipsModelValidations
            importer.set_status_info('Complete (with failures)', run)
            work1
          end
        end

        it 'no longer counts it as failed' do
          perform
          expect(run.reload.failed_relationships).to eq(0)
        end

        it 'marks the importer complete' do
          perform
          expect(Importer.find(importer.id).status).to eq('Complete')
        end
      end

      context 'when a failed relationship to a parent work links on a later run of the job' do
        let(:parent_entry) { work1_entry }
        let(:parent_record) { work1 }
        let(:child_entry) { work2_entry }
        let(:child_record) { work2 }
        let(:updated_parent) { work1 }

        it_behaves_like 'a failed relationship that links later'
      end

      context 'when a failed relationship to a parent collection links on a later run of the job' do
        let(:parent_entry) { collection1_entry }
        let(:parent_record) { collection1 }
        let(:child_entry) { work1_entry }
        let(:child_record) { work1 }

        it_behaves_like 'a failed relationship that links later'
      end

      context 'when called without an importer run' do
        subject(:perform) do
          create_relationships_job.perform(parent_identifier: 'missing-parent', failure_count: described_class.max_failure_count - 1)
        end

        before { allow(create_relationships_job).to receive(:find_record).with('missing-parent', nil).and_return([nil, nil]) }

        it 'returns the error on the last attempt instead of raising' do
          expect(perform).to match([a_string_including('missing-parent')])
        end
      end

      context 'when a parent never resolves and the last attempt fails' do
        subject(:perform) do
          create_relationships_job.perform(
            parent_identifier: 'no-such-parent',
            importer_run_id: run.id,
            failure_count: described_class.max_failure_count - 1
          )
        end
        let(:run) { importer.current_run }
        let!(:relationship) do
          create(:pending_relationship, importer_run_id: run.id, parent_id: 'no-such-parent', child_id: work1_entry.identifier, order: 1)
        end

        before do
          allow(ImporterRun).to receive(:update_counters).and_call_original
          allow(create_relationships_job).to receive(:find_record).with('no-such-parent', run.id).and_return([nil, nil])
          importer.set_status_info('Complete', run)
        end

        it 'names the missing parent on the relationship' do
          perform
          expect(relationship.reload.status_message).to include('no-such-parent')
        end

        it 'marks the importer as complete with failures' do
          perform
          expect(importer.reload.status).to eq('Complete (with failures)')
        end
      end

      context 'when adding a parent record that is not found' do
        let(:pending_rel_test) do
          create(:pending_relationship,
                 importer_run_id: importer.current_run.id,
                 parent_id: parent_identifier,
                 child_id: child_id,
                 order: 1)
        end
        let(:parent_identifier) { 'not_found' }
        let(:child_id) { work1_entry.identifier }

        before do
          allow(create_relationships_job).to receive(:find_record).with(parent_identifier, importer.current_run.id).and_return([nil, nil])
          allow(create_relationships_job).to receive(:find_record).with(child_id, importer.current_run.id).and_return([work1_entry, work1])
          pending_rel_test
        end

        it 'reschedules the job' do
          expect(ImporterRun).not_to receive(:update_counters).with(importer.current_run.id, hash_including(:failed_relationships))
          expect(create_relationships_job).to receive(:reschedule).with(parent_identifier: parent_identifier, importer_run_id: importer.current_run.id, run_user: importer.current_run.user, failure_count: 1)
          result = perform
          expect(result).to eq(["Parent record #{parent_identifier} not yet available for creating relationships with children records."])
        end
      end
    end

    describe 'when finishing a pass on a work fails' do
      let(:run) { importer.current_run }
      let(:updated_parent) { work1 }
      let!(:relationship) { create(:pending_relationship, importer_run_id: run.id, parent_id: work1_entry.identifier, child_id: work2_entry.identifier) }

      subject(:perform) { create_relationships_job.perform(parent_identifier: work1_entry.identifier, importer_run_id: run.id) }

      before do
        allow(create_relationships_job).to receive(:find_record).with(work1_entry.identifier, run.id).and_return([work1_entry, work1])
        allow(create_relationships_job).to receive(:find_record).with(work2_entry.identifier, run.id).and_return([work2_entry, work2])
        allow(Bulkrax.object_factory).to receive(:update_index).and_raise('index down')
      end

      it 'records the error, keeps the relationship and reschedules the pass' do
        expect(perform.map(&:message)).to include('index down')
        expect(PendingRelationship.exists?(relationship.id)).to be true
        expect(create_relationships_job).to have_received(:reschedule).with(hash_including(failure_count: 1))
      end

      it 'marks the relationship with the error, so a stalled ScheduleRelationshipsJob leaves it to the reschedule' do
        perform

        expect(relationship.reload.status_message).to eq 'index down'
        expect(PendingRelationship.pending).not_to include(relationship)
      end

      it 'counts the relationship as failed while it waits, and the importer as complete once the reschedule links it' do
        importer.set_status_info('Complete', run)

        perform
        expect(run.reload.failed_relationships).to eq 1
        expect(Importer.find(importer.id).status).to eq 'Complete (with failures)'

        allow(Bulkrax.object_factory).to receive(:update_index).and_return(true)
        retry_job = described_class.new
        allow(retry_job).to receive(:find_record).with(work1_entry.identifier, run.id).and_return([work1_entry, work1])
        allow(retry_job).to receive(:find_record).with(work2_entry.identifier, run.id).and_return([work2_entry, work2])
        retry_job.perform(parent_identifier: work1_entry.identifier, importer_run_id: run.id, failure_count: 1)

        expect(run.reload.failed_relationships).to eq 0
        expect(Importer.find(importer.id).status).to eq 'Complete'
      end

      it 'relates the child on the rescheduled pass' do
        perform
        allow(Bulkrax.object_factory).to receive(:update_index).and_return(true)
        retry_job = described_class.new
        allow(retry_job).to receive(:find_record).with(work1_entry.identifier, run.id).and_return([work1_entry, work1])
        allow(retry_job).to receive(:find_record).with(work2_entry.identifier, run.id).and_return([work2_entry, work2])
        allow(retry_job).to receive(:reschedule)

        retry_job.perform(parent_identifier: work1_entry.identifier, importer_run_id: run.id, failure_count: 1)

        expect(retry_job).not_to have_received(:reschedule)
        expect(PendingRelationship.exists?(relationship.id)).to be false
      end

      it "destroys the relationships while it holds the work's lock, so another pass cannot finish them too" do
        allow(Bulkrax.object_factory).to receive(:update_index).and_return(true)
        locked = false
        allow(create_relationships_job).to receive(:conditionally_acquire_lock_for).and_wrap_original do |method, *args, &block|
          locked = true
          method.call(*args, &block).tap { locked = false }
        end
        destroyed_while_locked = []
        allow_any_instance_of(PendingRelationship).to receive(:destroy).and_wrap_original do |method|
          destroyed_while_locked << locked
          method.call
        end

        perform

        expect(destroyed_while_locked).to eq [true]
      end
    end

    describe 'attaching file sets the Valkyrie object factory created unattached' do
      include_context 'with the Valkyrie memory adapter'

      let(:run) { importer.current_run }
      let(:fixture_path) { Bulkrax::Engine.root.join('spec', 'fixtures', 'removed.png').to_s }
      let(:work) { Hyrax.persister.save(resource: WorkResource.new(title: ['parent'])) }
      let(:titles) { %w[first second third] }
      let(:file_sets) { titles.index_with { |title| Hyrax.persister.save(resource: Hyrax::FileSet.new(title: [title])) } }
      let!(:uploads) do
        file_sets.transform_values do |file_set|
          Hyrax::UploadedFile.create!(file: File.open(fixture_path), user: run.user, file_set_uri: file_set.id.to_s)
        end
      end

      subject(:perform) { create_relationships_job.perform(parent_identifier: work.id.to_s, importer_run_id: run.id) }

      def relate(title, order: titles.index(title))
        create(:pending_relationship, importer_run_id: run.id, parent_id: work.id.to_s, child_id: title, order: order)
      end

      def members
        Hyrax.query_service.find_members(resource: Hyrax.query_service.find_by(id: work.id)).map { |member| member.title.first }
      end

      before do
        allow(create_relationships_job).to receive(:find_record).and_call_original
        file_sets.each do |title, file_set|
          allow(create_relationships_job).to receive(:find_record).with(title, run.id) { [nil, Hyrax.query_service.find_by(id: file_set.id)] }
        end
        allow(ValkyrieIngestJob).to receive(:perform_later).and_return(true)
      end

      it 'adds every file set in one pass, and queues each ingest once the work has its thumbnail' do
        titles.each { |title| relate(title) }
        thumbnails_when_queued = []
        allow(ValkyrieIngestJob).to receive(:perform_later) { thumbnails_when_queued << Hyrax.query_service.find_by(id: work.id).thumbnail_id }

        perform

        expect(members).to eq titles
        expect(Hyrax.query_service.find_by(id: work.id).representative_id).to eq file_sets['first'].id
        expect(thumbnails_when_queued).to eq [file_sets['first'].id] * 3
      end

      it 'queues one ingest when both the work row and the file set row name the relationship' do
        2.times { relate('first') }

        perform

        expect(ValkyrieIngestJob).to have_received(:perform_later).with(uploads['first']).once
      end

      it 'queues the ingest of a file set a killed pass attached but never queued' do
        Hyrax.persister.save(resource: work.tap { |w| w.member_ids = [file_sets['first'].id] })
        relate('first')

        perform

        expect(members).to eq ['first']
        expect(ValkyrieIngestJob).to have_received(:perform_later).with(uploads['first'])
      end

      it 'leaves a file set queued to two works in the first, failing the second without rescheduling it' do
        other_work = Hyrax.persister.save(resource: WorkResource.new(title: ['other']))
        relate('first')
        relate('second')
        queued_elsewhere = create(:pending_relationship, importer_run_id: run.id, parent_id: other_work.id.to_s, child_id: 'first', order: 0)
        perform

        other_job = described_class.new
        allow(other_job).to receive(:reschedule)
        allow(other_job).to receive(:find_record).and_call_original
        allow(other_job).to receive(:find_record).with('first', run.id) { [nil, Hyrax.query_service.find_by(id: file_sets['first'].id)] }
        other_job.perform(parent_identifier: other_work.id.to_s, importer_run_id: run.id)

        expect(members).to eq %w[first second]
        expect(Hyrax.query_service.find_by(id: other_work.id).member_ids).to be_empty
        expect(queued_elsewhere.reload.status_message).to eq "#{file_sets['first'].id} is already in work #{work.id}; adding it to work #{other_work.id} is not supported"
        expect(other_job).not_to have_received(:reschedule)
        expect(run.reload.failed_relationships).to eq 1
      end

      context 'when the file set row names no visibility' do
        let(:open_work) do
          Hyrax.persister.save(resource: WorkResource.new(title: ['open'])).tap do |open|
            open.visibility = 'open'
            open.permission_manager.acl.save
          end
        end

        def job_for(job)
          job.tap do |relationships_job|
            allow(relationships_job).to receive(:reschedule)
            allow(relationships_job).to receive(:find_record).and_call_original
            [file_sets['first'].id.to_s, 'first'].each do |child_id|
              allow(relationships_job).to receive(:find_record).with(child_id, run.id) { [nil, Hyrax.query_service.find_by(id: file_sets['first'].id)] }
            end
          end
        end

        def queue(parent, child_id: 'first', inherit: true)
          create(:pending_relationship, importer_run_id: run.id, parent_id: parent.id.to_s, child_id: child_id, order: 0, inherit_parent_visibility: inherit)
        end

        def visibility_of(file_set)
          Hyrax.query_service.find_by(id: file_set.id).visibility
        end

        it 'gives the file set the visibility of the work that attaches it' do
          queue(open_work)

          job_for(described_class.new).perform(parent_identifier: open_work.id.to_s, importer_run_id: run.id)

          expect(visibility_of(file_sets['first'])).to eq 'open'
        end

        it 'gives the work its visibility when the relationship names the file set by id' do
          queue(open_work, child_id: file_sets['first'].id.to_s)

          job_for(described_class.new).perform(parent_identifier: open_work.id.to_s, importer_run_id: run.id)

          expect(visibility_of(file_sets['first'])).to eq 'open'
        end

        context 'when the file set has its own running embargo' do
          let(:embargo) do
            Hyrax.persister.save(resource: Hyrax::Embargo.new(embargo_release_date: 1.month.from_now.to_date,
                                                              visibility_during_embargo: 'restricted', visibility_after_embargo: 'open'))
          end

          before do
            file_set = file_sets['first']
            file_set.embargo = embargo
            Hyrax::EmbargoManager.apply_embargo_for(resource: file_set)
            file_set.permission_manager.acl.save
            Hyrax.persister.save(resource: file_set)
          end

          it 'keeps it when a relationship to an open work attaches the file set' do
            queue(open_work)

            job_for(described_class.new).perform(parent_identifier: open_work.id.to_s, importer_run_id: run.id)

            expect(visibility_of(file_sets['first'])).to eq 'restricted'
            expect(Hyrax.query_service.find_by(id: file_sets['first'].id).embargo.embargo_release_date).to be_present
          end

          it 'keeps it when a re-import relates the file set to the open work it is already in' do
            Hyrax.persister.save(resource: open_work.tap { |w| w.member_ids = [file_sets['first'].id] })
            queue(open_work)

            job_for(described_class.new).perform(parent_identifier: open_work.id.to_s, importer_run_id: run.id)

            expect(visibility_of(file_sets['first'])).to eq 'restricted'
          end
        end

        it "gives a file set whose row named an embargo visibility its embargoed work's embargo" do
          embargo = Hyrax.persister.save(resource: Hyrax::Embargo.new(embargo_release_date: 1.month.from_now.to_date,
                                                                      visibility_during_embargo: 'restricted', visibility_after_embargo: 'open'))
          embargoed = Hyrax.persister.save(resource: WorkResource.new(title: ['embargoed']))
          embargoed.embargo = embargo
          Hyrax::EmbargoManager.apply_embargo_for(resource: embargoed)
          embargoed.permission_manager.acl.save
          embargoed = Hyrax.persister.save(resource: embargoed)
          queue(embargoed)

          job_for(described_class.new).perform(parent_identifier: embargoed.id.to_s, importer_run_id: run.id)

          expect(Hyrax.query_service.find_by(id: file_sets['first'].id).embargo.embargo_release_date.to_date).to eq embargo.embargo_release_date.to_date
        end

        it "gives the file set the visibility a work's ended but unreleased lease ends in" do
          lease = Hyrax.persister.save(resource: Hyrax::Lease.new(lease_expiration_date: 1.day.ago.to_date, visibility_during_lease: 'open',
                                                                  visibility_after_lease: 'restricted'))
          leased = Hyrax.persister.save(resource: WorkResource.new(title: ['lease ended']))
          leased.lease = lease
          leased.visibility = 'open'
          leased.permission_manager.acl.save
          leased = Hyrax.persister.save(resource: leased)
          queue(leased)

          job_for(described_class.new).perform(parent_identifier: leased.id.to_s, importer_run_id: run.id)

          expect(visibility_of(file_sets['first'])).to eq 'restricted'
        end

        it 'keeps the visibility a row named' do
          queue(open_work, inherit: false)

          job_for(described_class.new).perform(parent_identifier: open_work.id.to_s, importer_run_id: run.id)

          expect(visibility_of(file_sets['first'])).to eq 'restricted'
        end

        it "gives a file set created under an open work's lease the restricted visibility of the work that attaches it first" do
          lease = Hyrax.persister.save(resource: Hyrax::Lease.new(lease_expiration_date: 1.month.from_now.to_date, visibility_during_lease: 'open',
                                                                  visibility_after_lease: 'restricted'))
          leased_work = Hyrax.persister.save(resource: WorkResource.new(title: ['leased']))
          leased_work.lease = lease
          Hyrax::LeaseManager.apply_lease_for(resource: leased_work)
          leased_work.permission_manager.acl.save
          leased_work = Hyrax.persister.save(resource: leased_work)
          upload = Hyrax::UploadedFile.create!(file: File.open(fixture_path), user: run.user)
          factory = Bulkrax::ValkyrieObjectFactory.new(attributes: { 'title' => ['leased'], 'parents' => [leased_work.id.to_s], 'file' => [fixture_path] },
                                                       source_identifier_value: 'leased', work_identifier: :bulkrax_identifier,
                                                       work_identifier_search_field: 'bulkrax_identifier_tesim',
                                                       related_parents_parsed_mapping: 'parents', user: run.user, klass: Hyrax::FileSet)
          allow(factory).to receive(:find_record) { [nil, Hyrax.query_service.find_by(id: leased_work.id)] }
          created = factory.send(:create_file_set, uploaded_files: [upload.id])
          [work, leased_work].each do |parent|
            create(:pending_relationship, importer_run_id: run.id, parent_id: parent.id.to_s, child_id: 'leased', inherit_parent_visibility: true)
          end

          [work, leased_work].each do |parent|
            job = described_class.new
            allow(job).to receive(:reschedule)
            allow(job).to receive(:find_record).and_call_original
            allow(job).to receive(:find_record).with('leased', run.id) { [nil, Hyrax.query_service.find_by(id: created.id)] }
            job.perform(parent_identifier: parent.id.to_s, importer_run_id: run.id)
          end

          expect(Hyrax.query_service.find_parents(resource: created).map(&:id)).to eq [work.id]
          expect(Hyrax.query_service.find_by(id: created.id).visibility).to eq 'restricted'
          expect(Hyrax.query_service.find_by(id: created.id).lease).to be_nil
        end

        it 'keeps a file set re-imported under an open work, before its restricted work attached it, restricted in that work' do
          queue(work)
          queue(open_work)
          reimport = Bulkrax::ValkyrieObjectFactory.new(attributes: { 'title' => ['first'], 'parents' => [open_work.id.to_s] },
                                                        source_identifier_value: 'first', work_identifier: :bulkrax_identifier,
                                                        work_identifier_search_field: 'bulkrax_identifier_tesim',
                                                        related_parents_parsed_mapping: 'parents', user: run.user, klass: Hyrax::FileSet)
          allow(reimport).to receive(:object) { Hyrax.query_service.find_by(id: file_sets['first'].id) }
          allow(reimport).to receive(:perform_transaction_for) { Hyrax.query_service.find_by(id: file_sets['first'].id) }
          allow(reimport).to receive(:find_record) { [nil, Hyrax.query_service.find_by(id: open_work.id)] }
          reimport.send(:update_file_set, {})

          job_for(create_relationships_job).perform(parent_identifier: work.id.to_s, importer_run_id: run.id)
          job_for(described_class.new).perform(parent_identifier: open_work.id.to_s, importer_run_id: run.id)

          expect(members).to eq ['first']
          expect(Hyrax.query_service.find_by(id: open_work.id).member_ids).to be_empty
          expect(visibility_of(file_sets['first'])).to eq 'restricted'
        end
      end

      it 'attaches in row order, not the order the rows finished' do
        titles.reverse_each { |title| relate(title) }

        perform

        expect(members).to eq titles
      end

      it 'keeps the listed order for children named in one cell, which share an order' do
        titles.each { |title| relate(title, order: 1) }

        perform

        expect(members).to eq titles
      end

      it 'deletes the relationship only after its ingest is queued' do
        relationship = relate('first')
        kept_when_queued = nil
        allow(ValkyrieIngestJob).to receive(:perform_later) { kept_when_queued = PendingRelationship.exists?(relationship.id) }

        perform

        expect(kept_when_queued).to be true
        expect(PendingRelationship.exists?(relationship.id)).to be false
      end

      it 'leaves the relationship for the next pass when the worker dies before queueing' do
        relationship = relate('first')
        allow(create_relationships_job).to receive(:finish_linked_relationships)

        perform

        expect(members).to eq ['first']
        expect(PendingRelationship.exists?(relationship.id)).to be true
      end

      it 'records the error, queues nothing and keeps the relationship for the rescheduled pass when saving the work fails' do
        relationship = relate('first')
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:save!).and_raise('save failed')

        expect(perform.map(&:message)).to include('save failed')
        expect(ValkyrieIngestJob).not_to have_received(:perform_later)
        expect(PendingRelationship.exists?(relationship.id)).to be true
        expect(create_relationships_job).to have_received(:reschedule).with(hash_including(parent_identifier: work.id.to_s, failure_count: 1))
      end

      it 'queues the ingest on the rescheduled pass when indexing the work failed' do
        relationship = relate('first')
        allow(Bulkrax::ValkyrieObjectFactory).to receive(:update_index).and_raise('index down')
        perform
        expect(PendingRelationship.exists?(relationship.id)).to be true
        expect(ValkyrieIngestJob).not_to have_received(:perform_later)

        allow(Bulkrax::ValkyrieObjectFactory).to receive(:update_index).and_call_original
        retry_job = described_class.new
        allow(retry_job).to receive(:find_record).and_call_original
        allow(retry_job).to receive(:find_record).with('first', run.id) { [nil, Hyrax.query_service.find_by(id: file_sets['first'].id)] }
        retry_job.perform(parent_identifier: work.id.to_s, importer_run_id: run.id, failure_count: 1)

        expect(members).to eq ['first']
        expect(PendingRelationship.exists?(relationship.id)).to be false
        expect(ValkyrieIngestJob).to have_received(:perform_later).with(uploads['first']).once
      end

      it 'reschedules the pass when the lock on the work cannot be acquired' do
        relationship = relate('first')
        allow(create_relationships_job).to receive(:conditionally_acquire_lock_for).and_raise('lock unavailable')

        expect(perform.map(&:message)).to include('lock unavailable')
        expect(PendingRelationship.exists?(relationship.id)).to be true
        expect(create_relationships_job).to have_received(:reschedule).with(hash_including(failure_count: 1))
      end

      it 'records the error and keeps the relationship when the ingest is refused without raising' do
        relationship = relate('first')
        allow(ValkyrieIngestJob).to receive(:perform_later).and_return(false)

        expect(perform.map(&:message).join).to match(/Could not queue the ingest/)
        expect(PendingRelationship.exists?(relationship.id)).to be true
        expect(create_relationships_job).to have_received(:reschedule).with(hash_including(failure_count: 1))
      end

      it 'keeps the relationships it had not queued when queueing fails' do
        first = relate('first')
        second = relate('second')
        allow(ValkyrieIngestJob).to receive(:perform_later).with(uploads['second']).and_raise('queue down')

        expect(perform.map(&:message)).to include('queue down')
        expect(PendingRelationship.where(id: [first.id, second.id]).pluck(:id)).to eq [second.id]
      end

      it 'counts every relationship once when a retry finishes a pass whose queueing failed' do
        relate('first')
        relate('second')
        allow(ImporterRun).to receive(:update_counters).and_call_original
        allow(ValkyrieIngestJob).to receive(:perform_later).with(uploads['second']).and_raise('queue down')
        perform

        allow(ValkyrieIngestJob).to receive(:perform_later).with(uploads['second']).and_return(true)
        retry_job = described_class.new
        allow(retry_job).to receive(:find_record).and_call_original
        allow(retry_job).to receive(:find_record).with('second', run.id) { [nil, Hyrax.query_service.find_by(id: file_sets['second'].id)] }
        retry_job.perform(parent_identifier: work.id.to_s, importer_run_id: run.id, failure_count: 1)

        expect(run.reload.processed_relationships).to eq 2
      end

      it 'queues the ingest of the file sets it added when a later one fails' do
        relate('first')
        create(:pending_relationship, importer_run_id: run.id, parent_id: work.id.to_s, child_id: 'missing', order: 5)
        allow(create_relationships_job).to receive(:find_record).with('missing', run.id).and_return([nil, nil])

        perform

        expect(ValkyrieIngestJob).to have_received(:perform_later).with(uploads['first'])
      end

      it 'relates file sets that rows created at once' do
        factories = titles.map do |title|
          Bulkrax::ValkyrieObjectFactory.new(attributes: { 'title' => [title], 'parents' => [work.id.to_s], 'file' => [fixture_path] },
                                             source_identifier_value: title, work_identifier: :bulkrax_identifier,
                                             work_identifier_search_field: 'bulkrax_identifier_tesim', related_parents_parsed_mapping: 'parents',
                                             user: run.user, klass: Hyrax::FileSet).tap do |factory|
            allow(factory).to receive(:find_record) { [nil, Hyrax.query_service.find_by(id: work.id)] }
          end
        end
        new_uploads = Array.new(titles.size) { Hyrax::UploadedFile.create!(file: File.open(fixture_path), user: run.user) }
        created = factories.zip(new_uploads).map { |factory, upload| Thread.new { factory.send(:create_file_set, uploaded_files: [upload.id]) } }.map(&:value)
        expect(Hyrax.query_service.find_by(id: work.id).member_ids).to be_empty

        titles.zip(created).each do |title, file_set|
          allow(create_relationships_job).to receive(:find_record).with(title, run.id) { [nil, Hyrax.query_service.find_by(id: file_set.id)] }
          relate(title)
        end
        perform

        expect(Hyrax.query_service.find_by(id: work.id).member_ids).to eq created.map(&:id)
      end
    end
  end
end
