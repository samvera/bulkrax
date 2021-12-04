# frozen_string_literal: true

FactoryBot.define do
  factory :collection, class: 'Collection' do
    id { 'collection_id' }
    title { ['MyCollection'] }
    source { ['commons.ptsem.edu_MyCollection'] }
    identifier { ['commons.ptsem.edu_MyCollection'] }
  end

  factory :another_collection, class: 'Collection' do
    id { 'another_collection_id' }
    title { ['MyOtherCollection'] }
    source { ['commons.ptsem.edu_MyOtherCollection'] }
    identifier { ['commons.ptsem.edu_MyOtherCollection'] }
  end
end
