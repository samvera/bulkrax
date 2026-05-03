# frozen_string_literal: true

module Bulkrax
  # A minimal scope adapter that satisfies the Blacklight::SearchBuilder and
  # Hydra::AccessControlsEnforcement interface for export permission filtering.
  #
  # Blacklight::SearchBuilder expects the scope to respond to +blacklight_config+
  # and +current_ability+. In the Hyrax catalog this is the controller; for
  # Bulkrax exports a lightweight PORO is sufficient.
  class ExportScope
    attr_reader :current_ability

    def initialize(ability)
      @current_ability = ability
    end

    def blacklight_config
      @blacklight_config ||= Blacklight::Configuration.new
    end
  end
end
