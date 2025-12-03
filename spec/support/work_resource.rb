# frozen_string_literal: true

# Test Valkyrie resource for Bulkrax specs
class WorkResource < Hyrax::Resource
  include Hyrax::Schema(:basic_metadata)
  include Hyrax::Schema(:work_resource)
end
