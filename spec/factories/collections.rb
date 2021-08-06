# frozen_string_literal: true

FactoryBot.define do
  factory :collection, class: 'Collection' do
    id { 'collection_id' }
    title { ['MyCollection'] }
    source { ['commons.ptsem.edu_MyCollection'] }
    identifier { ['commons.ptsem.edu_MyCollection'] }
  end
end
