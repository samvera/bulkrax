# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe DeleteFileSetJob, type: :job do
    include_context 'with the Valkyrie memory adapter'

    let(:entry) { create(:bulkrax_entry) }
    let(:importer_run) { create(:bulkrax_importer_run) }
    let(:file_set) { Hyrax.persister.save(resource: Hyrax::FileSet.new(title: ['first'])) }
    let!(:work) { Hyrax.persister.save(resource: WorkResource.new(title: ['parent'], member_ids: [file_set.id])) }

    before do
      # Hyrax's lock manager needs Redis
      allow_any_instance_of(Hyrax::LockManager).to receive(:lock).and_yield # rubocop:disable RSpec/AnyInstance
      factory = ValkyrieObjectFactory.new(attributes: {}, source_identifier_value: 'fs-1', work_identifier: :bulkrax_identifier,
                                          work_identifier_search_field: 'bulkrax_identifier_tesim', klass: Hyrax::FileSet)
      allow(factory).to receive(:find).and_return(file_set)
      allow(entry).to receive(:factory).and_return(factory)

      described_class.new.perform(entry, importer_run)
    end

    it 'publishes the work without the file set, so the work is reindexed' do
      expect(Hyrax.publisher).to have_received(:publish)
        .with('object.metadata.updated', hash_including(object: having_attributes(id: work.id, member_ids: [])))
    end
  end
end
