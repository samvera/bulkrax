# frozen_string_literal: true
require 'dry/container'

module Bulkrax
  class Container
    extend Dry::Container::Mixin
    
    CreateWithBulkBehavior = 'create_with_bulk_behavior'.freeze
    UpdateWithBulkBehavior = 'update_with_bulk_behavior'.freeze
    AddBulkraxFiles = 'add_bulkrax_files'.freeze

    namespace "work_resource" do |ops|
      ops.register CreateWithBulkBehavior do
        steps = Hyrax::Transactions::WorkCreate::DEFAULT_STEPS.dup
        steps[steps.index("work_resource.add_file_sets")] = "work_resource.#{Bulkrax::Container::AddBulkraxFiles}"

        Hyrax::Transactions::WorkCreate.new(steps: steps)
      end

      ops.register UpdateWithBulkBehavior do
        steps = Hyrax::Transactions::WorkUpdate::DEFAULT_STEPS.dup
        steps[steps.index("work_resource.add_file_sets")] = "work_resource.#{Bulkrax::Container::AddBulkraxFiles}"

        Hyrax::Transactions::WorkUpdate.new(steps: steps)
      end

      # TODO: uninitialized constant Bulkrax::Container::InlineUploadHandler
      # ops.register "add_file_sets" do
      #   Hyrax::Transactions::Steps::AddFileSets.new(handler: InlineUploadHandler)
      # end

      ops.register AddBulkraxFiles do
        Bulkrax::Steps::AddFiles.new
      end
    end
  end
end
Hyrax::Transactions::Container.merge(Bulkrax::Container)