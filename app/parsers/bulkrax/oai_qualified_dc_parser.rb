# frozen_string_literal: true

module Bulkrax
  class OaiQualifiedDcParser < OaiDcParser
    def entry_class
      OaiQualifiedDcEntry
    end
  end
end
