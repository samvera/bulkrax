# frozen_string_literal: true

FactoryBot.define do
  factory :work, class: 'Work' do
    id { 'work_id' }
    title { ['A Work'] }
  end

  factory :another_work, class: 'Work' do
    id { 'another_work_id' }
    title { ['Another Work'] }
  end
end
