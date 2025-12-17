# frozen_string_literal: true

module Bulkrax
  # Utility classes
  class SampleCsvService::FilePathGenerator
    def self.default_path
      Rails.root.join('tmp', 'imports', "bulkrax_template_#{timestamp}.csv")
    end

    def self.timestamp
      Time.now.utc.strftime('%Y%m%d_%H%M%S')
    end
  end
end
