# frozen_string_literal: true

FactoryBot.define do
  factory :object_factory, class: 'Bulkrax::ObjectFactory' do
    initialize_with do
      new(
        attributes: {},
        source_identifier_value: :source_identifier,
        work_identifier: :source,
        work_identifier_search_field: 'source_sim',
        entry: FactoryBot.build(:bulkrax_entry)
      )
    end
  end
end
