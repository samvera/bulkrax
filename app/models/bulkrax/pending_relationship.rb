# frozen_string_literal: true

module Bulkrax
  class PendingRelationship < ApplicationRecord
    belongs_to :importer_run

    # Ideally we wouldn't have a column named "order", as it is a reserved SQL term.  However, if we
    # quote the column, all is well...for the application.
    scope :ordered, -> { order("#{quoted_table_name}.#{connection.quote_column_name('order')}") }
  end
end
