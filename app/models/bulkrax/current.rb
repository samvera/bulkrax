# frozen_string_literal: true

module Bulkrax
  # Console and rake sessions run outside the Rails executor, so they keep
  # this state until +Bulkrax::Current.reset+ is called.
  class Current < ActiveSupport::CurrentAttributes
    attribute :schema_cache
  end
end
