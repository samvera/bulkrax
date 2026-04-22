# frozen_string_literal: true

module Bulkrax
  # Coerces a split pattern into a Regexp for String#split.
  #
  # Bulkrax field mappings are persisted as JSON in several host applications
  # (e.g. Hyku), so the `split` value for a mapping can show up in several
  # forms and we need a single policy that handles all of them:
  #
  # * nil / blank           → `nil` (no split)
  # * already a Regexp      → returned unchanged
  # * `true`                → {Bulkrax.multi_value_element_split_on}
  # * String, any content   → `Regexp.new(str)` — the String is treated as a
  #                           regex source, matching the long-standing
  #                           contract in {Bulkrax::ApplicationMatcher}.
  #                           This means `"\\|"` → `/\|/` and a serialised
  #                           regex like `"(?-mix:\\s*[;|]\\s*)"` rebuilds
  #                           into an equivalent Regexp.
  #
  # This is the single place in the gem that translates stored split
  # configuration into the value consumed by String#split — import,
  # validation, and hierarchy code paths all route through here so the
  # behaviour is consistent regardless of how the mapping was persisted.
  module SplitPatternCoercion
    def self.coerce(split_val)
      return nil if split_val.blank?
      return Bulkrax.multi_value_element_split_on if split_val == true
      return split_val if split_val.is_a?(Regexp)
      return split_val unless split_val.is_a?(String)

      Regexp.new(split_val)
    rescue RegexpError
      split_val
    end
  end
end
