# frozen_string_literal: true

class WorkResource < Hyrax::Work
  include Hyrax::Schema(:basic_metadata)
  include Hyrax::Schema(:work_resource)
end
