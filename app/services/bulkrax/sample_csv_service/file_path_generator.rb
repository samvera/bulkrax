# frozen_string_literal: true

module Bulkrax
  # Utility classes
  class SampleCsvService::FilePathGenerator
    def self.default_path
      path = Rails.root.join('tmp', 'imports', "bulkrax_template_#{timestamp}.csv")
      FileUtils.mkdir_p(path.dirname.to_s)
      path
    end

    def self.timestamp
      Time.current.utc.strftime('%Y%m%d_%H%M%S')
    end
  end
end
