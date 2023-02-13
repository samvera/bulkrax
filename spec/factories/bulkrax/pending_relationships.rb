# frozen_string_literal: true

FactoryBot.define do
  factory :pending_relationship_collection_parent, class: 'Bulkrax::PendingRelationship' do
    association :importer_run, factory: :bulkrax_importer_run
    parent_id { 'entry_collection' }
    child_id { 'entry_work' }
  end

  factory :pending_relationship_collection_child, class: 'Bulkrax::PendingRelationship' do
    association :importer_run, factory: :bulkrax_importer_run
    parent_id { 'parent_entry_collection' }
    child_id { 'child_entry_collection' }
  end

  factory :pending_relationship_work_parent, class: 'Bulkrax::PendingRelationship' do
    association :importer_run, factory: :bulkrax_importer_run
    parent_id { 'parent_entry_work' }
    child_id { 'child_entry_work' }
  end

  factory :bad_pending_relationship, class: 'Bulkrax::PendingRelationship' do
    association :importer_run, factory: :bulkrax_importer_run
    parent_id { 'entry_work' }
    child_id { 'entry_collection' }
  end
end
