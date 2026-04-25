# frozen_string_literal: true

module Bulkrax
  # Single source of truth for resolving CSV column names ↔ canonical
  # mapping keys, so the import pipeline (HasMatchers#field_to) and the
  # guided-import validator agree on which columns feed which fields.
  module FieldResolver
    # Given a raw CSV header, return every canonical mapping key the
    # header feeds — walking every entry in `from:` and the mapping key
    # itself. Mirrors the long-standing behavior of
    # HasMatchers#field_to.
    #
    # @param mapping [Hash, nil] field_mappings for a parser (keys are
    #   canonical field names, values are option hashes with `from:`)
    # @param header [String] a CSV header
    # @return [Array<String>] canonical keys the header feeds; falls back
    #   to `[header]` when no mapping matches, preserving field_to's
    #   "unknown header is its own canonical name" contract.
    def self.fields_for_header(mapping, header)
      fields = mapping&.map do |key, value|
        return [header] if value.nil?

        if value['from'].instance_of?(Array)
          key if value['from'].include?(header) || key == header
        elsif value['from'] == header || key == header
          key
        end
      end&.compact

      return [header] if fields.blank?

      fields
    end

    # Inverse of #fields_for_header: given a canonical mapping key,
    # return every CSV header alias that ingests into it. Includes every
    # entry in `from:` plus the mapping key itself (which is always an
    # implicit alias regardless of `from:`).
    #
    # @param mapping [Hash, nil]
    # @param canonical_key [String] a canonical mapping key (e.g. 'file')
    # @return [Array<String>] deduplicated list of header aliases
    def self.headers_for_field(mapping, canonical_key)
      entry = mapping&.dig(canonical_key) || {}
      aliases = Array(entry['from'] || entry[:from])
      (aliases + [canonical_key]).uniq
    end

    # For flag-resolved mappings (`source_identifier: true`,
    # `related_parents_field_mapping: true`, etc.), pick the single
    # CSV header that should be read into the canonical record key.
    # Prefers an alias present in the CSV's actual headers; falls back
    # to the first alias when none match (preserving today's behavior
    # for back-compat). Returns nil if no mapping is flagged.
    #
    # @param mapping [Hash, nil]
    # @param flag [String] e.g. 'source_identifier' or 'related_parents_field_mapping'
    # @param headers [Array<String>] the actual CSV header row
    # @return [String, nil] the chosen alias
    def self.present_header_for_flag(mapping, flag, headers)
      flagged_key, flagged_value = (mapping || {}).find { |_k, v| v.is_a?(Hash) && v[flag] == true }
      return nil unless flagged_key

      aliases = Array(flagged_value['from'] || flagged_value[:from])
      candidates = (aliases + [flagged_key]).uniq

      header_set = Array(headers).map(&:to_s).to_set
      candidates.find { |c| header_set.include?(c.to_s) } || aliases.first || flagged_key
    end
  end
end
