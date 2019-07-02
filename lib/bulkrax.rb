require "bulkrax/engine"

module Bulkrax
  class << self
    mattr_accessor :parsers
    self.parsers = [
      { name: "OAI - Dublin Core", class_name: "Bulkrax::OaiDcParser", partial: 'oai_fields' },
      { name: "OAI - Qualified Dublin Core", class_name: "Bulkrax::OaiQualifiedDcParser", partial: 'oai_fields' },
      { name: "CSV - Comma Separated Values", class_name: "Bulkrax::CsvParser", partial: 'csv_fields' }
    ]
  end

  # this function maps the vars from your app into your engine
  def self.setup(&block)
    yield self
  end

end
