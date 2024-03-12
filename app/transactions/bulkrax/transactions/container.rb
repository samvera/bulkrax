# frozen_string_literal: true
require 'dry/container'

module Bulkrax
  module Transactions
    class Container
      extend Dry::Container::Mixin

      CREATE_WITH_BULK_BEHAVIOR_STEPS = begin
        steps = Hyrax::Transactions::WorkCreate::DEFAULT_STEPS.dup
        # steps[steps.index("work_resource.add_file_sets")] = "work_resource.add_bulkrax_files"
        steps
      end.freeze
      UPDATE_WITH_BULK_BEHAVIOR_STEPS = begin
        steps = Hyrax::Transactions::WorkUpdate::DEFAULT_STEPS.dup
        # steps[steps.index("work_resource.add_file_sets")] = "work_resource.add_bulkrax_files"
        steps
      end.freeze

      namespace "work_resource" do |ops|
        ops.register 'create_with_bulk_behavior' do
          Hyrax::Transactions::WorkCreate.new(steps: CREATE_WITH_BULK_BEHAVIOR_STEPS)
        end

        ops.register 'update_with_bulk_behavior' do
          Hyrax::Transactions::WorkUpdate.new(steps: UPDATE_WITH_BULK_BEHAVIOR_STEPS)
        end

        # TODO: Need to register step for uploads handler?
        # ops.register "add_file_sets" do
        #   Hyrax::Transactions::Steps::AddFileSets.new
        # end

        ops.register 'add_bulkrax_files' do
          Bulkrax::Transactions::Steps::AddFiles.new
        end
      end

      namespace "file_set_resource" do |ops|
        # TODO: to implement
      end
    end
  end
end
Hyrax::Transactions::Container.merge(Bulkrax::Transactions::Container)
