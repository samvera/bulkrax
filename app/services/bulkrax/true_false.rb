# frozen_string_literal: true

module Bulkrax
  # How Bulkrax reads a true/false CSV cell, whether a flag column such as
  # `delete` or a true/false property. An empty cell is false, since a
  # property has no default to fall back on.
  module TrueFalse
    # @return [Boolean, nil] nil when the value is neither true nor false
    def self.cast(value)
      return value if [true, false].include?(value)

      case value.to_s.strip.downcase
      when '', 'false', 'f', 'no', 'n', 'off', '0' then false
      when 'true', 't', 'yes', 'y', 'on', '1' then true
      end
    end
  end
end
