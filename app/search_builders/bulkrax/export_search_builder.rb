# frozen_string_literal: true

module Bulkrax
  class ExportSearchBuilder < Blacklight::SearchBuilder
    include Hydra::AccessControlsEnforcement

    self.default_processor_chain = [:add_access_controls_to_solr_params]
  end
end
