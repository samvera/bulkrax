# frozen_string_literal: true

FactoryBot.define do
  factory :object_factory, class: 'Bulkrax::ObjectFactory' do
    initialize_with do
      new(
        attributes: {},
        source_identifier_value: :source_identifier,
        work_identifier: :source,
        collection_field_mapping: :collection
      )
    end
  end
end
