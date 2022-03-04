FactoryBot.define do
  factory :pending_relationship do
    importer_run { nil }
    parent { "MyString" }
    child { "MyString" }
  end
end
