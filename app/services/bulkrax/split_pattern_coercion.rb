# frozen_string_literal: true

module Bulkrax
  # Coerces a stored split pattern into a Regexp suitable for String#split.
  #
  # Bulkrax field mappings are persisted as JSON in several host applications
  # (e.g. Hyku), so the `split` value for a mapping can show up in several
  # forms. This module is the single place that normalises them:
  #
  # * nil / blank           → `nil` (caller should treat as "no split")
  # * already a Regexp      → returned unchanged
  # * `true`                → {Bulkrax.multi_value_element_split_on}
  # * String, any content   → `Regexp.new(str)` — the String is treated as a
  #                           regex source, matching the long-standing
  #                           contract in {Bulkrax::ApplicationMatcher}.
  #                           `"\\|"` → `/\|/`; a serialised regex like
  #                           `"(?-mix:\\s*[;|]\\s*)"` rebuilds into an
  #                           equivalent Regexp.
  # * invalid regex source  → `nil` (we neither raise nor hand back an
  #                           unusable value to String#split).
  # * any other type        → `nil` (likewise — never returns something
  #                           String#split can't accept).
  #
  # Import, validation, and hierarchy code paths all route through here so
  # the behaviour is consistent regardless of how the mapping was persisted.
  #
  # @param split_val [nil, true, Regexp, String, Object] the configured split
  # @return [nil, Regexp] a pattern ready for String#split, or nil when
  #   no usable pattern can be derived from the input.
  module SplitPatternCoercion
    def self.coerce(split_val)
      return nil if split_val.blank?
      return Bulkrax.multi_value_element_split_on if split_val == true
      return split_val if split_val.is_a?(Regexp)
      return nil unless split_val.is_a?(String)

      Regexp.new(split_val)
    rescue RegexpError
      nil
    end
  end
end
