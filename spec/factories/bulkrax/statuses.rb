# frozen_string_literal: true

FactoryBot.define do
  factory :bulkrax_status, class: 'Status' do
    status_message { "MyString" }
    error_class { "MyString" }
    error_message { "MyString" }
    error_backtrace { "MyText" }
    statusable_id { 1 }
    statusable_type { "MyString" }
    runnable_id { 1 }
    runnable_type { "MyString" }
  end
end
