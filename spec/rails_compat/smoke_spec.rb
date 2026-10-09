# frozen_string_literal: true

return unless ENV['BULKRAX_WITH_HYRAX'] == 'false'

require_relative '../rails_compat_app/config/environment'
require_relative '../shared/serialized_attributes'

RSpec.describe 'Bulkrax Rails compatibility' do
  before(:all) do
    ActiveRecord::Migration.verbose = false
    ActiveRecord::MigrationContext.new(Bulkrax::Engine.paths['db/migrate'].expanded).migrate
    [Bulkrax::Importer, Bulkrax::Exporter, Bulkrax::Entry, Bulkrax::Status].each(&:reset_column_information)
  end

  it 'boots the engine without repository dependencies' do
    expect(Rails.application.initialized?).to be true
    expect(Bulkrax::Engine.routes.url_helpers.importers_path).to eq('/bulkrax/importers')
    expect(Gem.loaded_specs).not_to have_key('hyrax')
    expect(defined?(Hyrax::Engine)).to be_nil
    expect(defined?(ActiveFedora)).to be_nil
    expect(defined?(Wings)).to be_nil
  end

  it 'uses safe non-Hyrax configuration defaults' do
    expect(Bulkrax.curation_concerns).to eq([])
    expect(Bulkrax.file_model_class).to eq(File)
    expect(Bulkrax.collection_model_class).to be_nil
    expect(Bulkrax.config.ingest_queue_name).to eq(:import)
    expect(Bulkrax.solr_key_for_member_file_ids).to eq('file_ids_ssim')
  end

  it 'migrates the engine tables' do
    expect(ActiveRecord::Base.connection.tables).to include('bulkrax_importers', 'bulkrax_entries', 'bulkrax_statuses')
  end

  include_examples 'persisted Bulkrax serialization'
end
