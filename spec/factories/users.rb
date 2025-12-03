# frozen_string_literal: true

FactoryBot.define do
  factory :base_user, class: User do
    sequence(:email) { |_n| "email-#{srand}@test.com" }
    password { 'a password' }
    password_confirmation { 'a password' }

    factory :bulkrax_user do
    end
  end
end
