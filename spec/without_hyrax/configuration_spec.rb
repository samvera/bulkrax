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

  it 'keeps the multi-value split pattern an app configures' do
    previous = Bulkrax.config.multi_value_element_split_on
    Bulkrax.config.multi_value_element_split_on = /\s*;\s*/

    expect(Bulkrax.multi_value_element_split_on).to eq(/\s*;\s*/)
  ensure
    Bulkrax.config.multi_value_element_split_on = previous
  end

  it 'keeps the multi-value join an app configures' do
    previous = Bulkrax.config.multi_value_element_join_on
    Bulkrax.config.multi_value_element_join_on = '; '

    expect(Bulkrax.multi_value_element_join_on).to eq('; ')
  ensure
    Bulkrax.config.multi_value_element_join_on = previous
  end
end
