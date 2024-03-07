# frozen_string_literal: true
require 'dry/container'

module Bulkrax
  module Transactions
    class Container
      extend Dry::Container::Mixin

      ADD_BULKRAX_FILES = 'add_bulkrax_files'
      CREATE_WITH_BULK_BEHAVIOR = 'create_with_bulk_behavior'
      CREATE_WITH_BULK_BEHAVIOR_STEPS = begin
        steps = Hyrax::Transactions::WorkCreate::DEFAULT_STEPS.dup
        steps[steps.index("work_resource.add_file_sets")] = "work_resource.#{Bulkrax::Transactions::Container::ADD_BULKRAX_FILES}"
        steps
      end.freeze
      COLLECTION_CREATE_WITH_BULK_BEHAVIOR = begin
      steps = Hyrax::Transactions::CollectionCreate::DEFAULT_STEPS.dup
      # steps[steps.index("work_resource.add_file_sets")] = "work_resource.#{Bulkrax::Transactions::Container::ADD_BULKRAX_FILES}"
      steps
    end.freeze
      UPDATE_WITH_BULK_BEHAVIOR = 'update_with_bulk_behavior'
      UPDATE_WITH_BULK_BEHAVIOR_STEPS = begin
        steps = Hyrax::Transactions::WorkUpdate::DEFAULT_STEPS.dup
        steps[steps.index("work_resource.add_file_sets")] = "work_resource.#{Bulkrax::Transactions::Container::ADD_BULKRAX_FILES}"
        steps
      end.freeze

      namespace "collection_resource" do |ops|
        ops.register COLLECTION_CREATE_WITH_BULK_BEHAVIOR do
          Hyrax::Transactions::CollectionCreate.new(steps: COLLECTION_CREATE_WITH_BULK_BEHAVIOR_STEPS)
        end

      end

      namespace "work_resource" do |ops|
        ops.register CREATE_WITH_BULK_BEHAVIOR do
          Hyrax::Transactions::WorkCreate.new(steps: CREATE_WITH_BULK_BEHAVIOR_STEPS)
        end

        ops.register UPDATE_WITH_BULK_BEHAVIOR do
          Hyrax::Transactions::WorkUpdate.new(steps: UPDATE_WITH_BULK_BEHAVIOR_STEPS)
        end

        # TODO: Need to register step for uploads handler?
        # ops.register "add_file_sets" do
        #   Hyrax::Transactions::Steps::AddFileSets.new
        # end

        ops.register ADD_BULKRAX_FILES do
          Bulkrax::Transactions::Steps::AddFiles.new
        end
      end

      namespace "file_set_resource" do |ops|
        # TODO:
      end
    end
  end
end
Hyrax::Transactions::Container.merge(Bulkrax::Transactions::Container)
