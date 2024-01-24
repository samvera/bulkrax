# frozen_string_literal: true
require 'dry/container'

module Bulkrax
  module Transactions
    class Container
      extend Dry::Container::Mixin

      namespace "work_resource" do |ops|
        ops.register "create_with_bulk_behavior" do
          steps = Hyrax::Transactions::WorkCreate::DEFAULT_STEPS.dup
          steps[steps.index("work_resource.add_file_sets")] = "work_resource.add_bulkrax_files"

          Hyrax::Transactions::WorkCreate.new(steps: steps)
        end

        ops.register "update_with_bulk_behavior" do
          steps = Hyrax::Transactions::WorkUpdate::DEFAULT_STEPS.dup
          steps[steps.index("work_resource.add_file_sets")] = "work_resource.add_bulkrax_files"

          Hyrax::Transactions::WorkUpdate.new(steps: steps)
        end

        # TODO: uninitialized constant Bulkrax::Transactions::Container::InlineUploadHandler
        # ops.register "add_file_sets" do
        #   Hyrax::Transactions::Steps::AddFileSets.new(handler: InlineUploadHandler)
        # end

        ops.register "add_bulkrax_files" do
          Bulkrax::Transactions::Steps::AddFiles.new
        end
      end
    end
  end
end
Hyrax::Transactions::Container.merge(Bulkrax::Transactions::Container)