# frozen_string_literal: true

return unless ENV['BULKRAX_WITH_HYRAX'] == 'false'

require_relative '../rails_compat_app/config/environment'

RSpec.describe 'Configuring Bulkrax without Hyrax' do
  it 'keeps the collection model an app configures' do
    collection_model = Class.new
    previous = Bulkrax.config.collection_model_class
    Bulkrax.config.collection_model_class = collection_model

    expect(Bulkrax.collection_model_class).to eq(collection_model)
  ensure
    Bulkrax.config.collection_model_class = previous
  end
end
