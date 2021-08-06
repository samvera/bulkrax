# frozen_string_literal: true

FactoryBot.define do
  factory :bulkrax_status, class: 'Bulkrax::Status' do
    status_message { "MyString" }
    error_class { "MyString" }
    error_message { "MyString" }
    error_backtrace { ["MyText"] }
    statusable { build(:bulkrax_entry) }
    runnable { build(:bulkrax_importer_run) }
  end
end
