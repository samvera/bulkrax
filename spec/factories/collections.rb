FactoryBot.define do
  factory :collection, class: 'Collection' do
    id { 'collection_id' }
    title { ['MyCollection'] }
  end
end
