# frozen_string_literal: true

module Bulkrax
  # The purpose of this model is to provide a means of capturing (for later use) the derivatives
  # that are associated with a Bulkrax::Entry (for importers).
  #
  # @see https://github.com/samvera-labs/bulkrax/issues/760
  class EntryDerivative < ApplicationRecord
    belongs_to :entry

    # These are enforced on the database schema, but we might as well telegraph that here.
    validates :derivative_type, :path, presence: true
  end
end
