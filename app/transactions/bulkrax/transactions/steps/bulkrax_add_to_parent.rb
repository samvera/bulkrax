# frozen_string_literal: true

require "dry/monads"

module Bulkrax
  module Transactions
    module Steps
      ##
      # Hyrax's association modeling changed-ish with Valkyrie.
      class BulkraxAddToParent
        include Dry::Monads[:result]

        ##
        # @param [Class] handler
        def initialize(handler: Hyrax::WorkUploadsHandler)
          @handler = handler
        end

        ##
        # @param obj [Valkyrie::Resource] Maybe a work, maybe collection; we'll
        #        find out.
        #
        # @param parent_ids [Valkyrie::ID, #to_s, Array<Valkyrie::ID, #to_s>]
        #        we'll go ahead and assume this is scalar or an array, and loop
        #        through with the correct switching logic
        #
        # @return [Dry::Monads::Result]
        def call(obj, parent_ids:)
          Array.wrap(parent_ids).each do |parent_id|
            parent = find_parent(parent_id)
            associate(child: obj, parent: parent)
            # TODO: Capture failures
          end

          Success(obj)
        end

        private

        # TODO: Make it work!
        def associate(child:, parent:)
          case child
          when Bulkrax.collection_model_class
            associate_collection(child: child, parent: parent)
          when Bulkrax.file_model_class
            associate_file(child: child, parent: parent)
          else
            associate_work(child: child, parent: parent)
          end
        end

        def associate_collection(child:, parent:); end

        def associate_work(child:, parent:); end

        def associate_file(child:, parent:); end
      end
    end
  end
end
