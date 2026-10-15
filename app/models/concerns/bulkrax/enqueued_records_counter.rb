# frozen_string_literal: true

module Bulkrax
  module EnqueuedRecordsCounter
    extend ActiveSupport::Concern

    class_methods do
      # A single UPDATE, so concurrent jobs cannot both pass the zero check and count below zero.
      def decrement_enqueued_records(id)
        where(id: id).where('enqueued_records > 0').update_all('enqueued_records = enqueued_records - 1') # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
