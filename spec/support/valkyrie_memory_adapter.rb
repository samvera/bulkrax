# frozen_string_literal: true

# Saves Valkyrie resources in memory, so the Valkyrie import path runs without Fedora,
# with ValkyrieObjectFactory as the object factory. Hyrax's event listeners need a full
# Hyrax app, so nothing is published.
RSpec.shared_context 'with the Valkyrie memory adapter' do
  let(:metadata_adapter) { Valkyrie::Persistence::Memory::MetadataAdapter.new }

  before do
    [Hyrax::CustomQueries::Navigators::ChildFileSetsNavigator,
     Hyrax::CustomQueries::Navigators::FindFiles,
     Hyrax::CustomQueries::FindAccessControl].each do |handler|
      metadata_adapter.query_service.custom_queries.register_query_handler(handler)
    end
    allow(Valkyrie.config).to receive(:metadata_adapter).and_return(metadata_adapter)
    allow(Bulkrax).to receive(:object_factory).and_return(Bulkrax::ValkyrieObjectFactory)
    allow(Bulkrax).to receive(:file_model_class).and_return(Hyrax::FileSet)
    allow(Hyrax.publisher).to receive(:publish)
  end
end
