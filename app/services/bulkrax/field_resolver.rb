# frozen_string_literal: true

module Bulkrax
  # Single source of truth for resolving CSV column names ↔ canonical
  # mapping keys, so the import pipeline (HasMatchers#field_to) and the
  # guided-import validator agree on which columns feed which fields.
  module FieldResolver
    # Given a raw CSV header, return every canonical mapping key the
    # header feeds, checking every entry in `from:` and the mapping key
    # itself.
    #
    # @param mapping [Hash, nil] field_mappings for a parser (keys are
    #   canonical field names, values are option hashes with `from:`)
    # @param header [String] a CSV header
    # @return [Array<String>] canonical keys the header feeds; falls back
    #   to `[header]` when no mapping matches, preserving field_to's
    #   "unknown header is its own canonical name" contract.
    def self.fields_for_header(mapping, header)
      fields = mapping&.map do |key, value|
        next if value.nil?

        from = from_value(value)
        if from.is_a?(Array)
          key if from.include?(header) || key == header
        elsif from == header || key == header
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
      aliases = Array(from_value(entry))
      (aliases + [canonical_key]).uniq
    end

    # A single-valued field's column and value as import reads them
    # (HasMatchers#add_metadata): the last column mapped to the field wins,
    # blank or not, through the mapping's matcher when there is one, then
    # stripped; an excluded mapping, or one filling a nested `object:`, is
    # skipped. Guided validation and the CSV parser both use it.
    #
    # @param raw_row [Hash{String => String}] the row's cells by header
    # @param field [String] a single-valued field, such as 'id' or 'visibility'
    # @return [Array(String, String), nil] the header and its value (nil when blank)
    def self.row_value(raw_row, mapping, field)
      entry = mapping&.dig(field)
      return if option(entry, 'excluded') || option(entry, 'object').present?

      header = raw_row.keys.reverse.find do |key|
        fields_for_header(mapping, key_without_numbers(key)).include?(field)
      end
      [header, matched_cell(field, entry, raw_row[header]).to_s.strip.presence] if header
    end

    # A multi-valued field's values as import reads them (HasMatchers#add_metadata):
    # each column mapped to the field, in order, through the mapping's matcher when
    # there is one, without blanks or repeats; an excluded mapping, or one filling
    # a nested `object:`, gives none.
    #
    # @param raw_row [Hash{String => String}] the row's cells by header
    # @param field [String] a multi-valued field, such as 'file'
    # @param parse [Boolean] false to skip the mapping's `parsed:` step, which for
    #   remote files requests each url
    # @return [Array<String>]
    def self.row_values(raw_row, mapping, field, parse: true)
      entry = mapping&.dig(field)
      return [] if option(entry, 'excluded') || option(entry, 'object').present?

      entry = entry.to_h.except('parsed', :parsed) if entry && !parse

      values = raw_row.each_with_object([]) do |(header, cell), found|
        next unless fields_for_header(mapping, key_without_numbers(header)).include?(field)

        found.concat(Array.wrap(matched_cell(field, entry, cell)))
      end
      values.map { |value| value.to_s.strip }.reject(&:blank?).uniq
    end

    def self.matched_cell(field, entry, cell)
      entry ? Bulkrax::CsvEntry.matcher(field, entry.to_h.symbolize_keys).result(nil, cell) : cell
    end
    private_class_method :matched_cell

    # The header import maps, after dropping column numbering such as
    # `creator_1` or `1_creator`.
    def self.key_without_numbers(header)
      header.to_s.gsub(/_\d+/, '').sub(/^\d+_/, '')
    end

    # Whether import reads `header` into a field that `aliases` names.
    #
    # @param header [String, Symbol] a CSV header
    # @param aliases [Array<String, Symbol>]
    # @return [Boolean]
    def self.header_for_any?(header, aliases)
      Array(aliases).map(&:to_s).include?(key_without_numbers(header))
    end

    # For flag-resolved mappings (`source_identifier: true`,
    # `related_parents_field_mapping: true`, etc.), pick the single
    # CSV header that should be read into the canonical record key.
    # Prefers an alias present in the CSV's actual headers; falls back
    # to the first alias when none match. Returns nil if no mapping is
    # flagged.
    #
    # @param mapping [Hash, nil]
    # @param flag [String] e.g. 'source_identifier' or 'related_parents_field_mapping'
    # @param headers [Array<String>] the actual CSV header row
    # @return [String, nil] the chosen alias
    def self.present_header_for_flag(mapping, flag, headers)
      key = flagged_key(mapping, flag)
      return nil unless key

      aliases = Array(from_value(mapping[key]))
      candidates = (aliases + [key]).uniq

      header_set = Array(headers).map(&:to_s).to_set
      candidates.find { |c| header_set.include?(c.to_s) } || aliases.first || key
    end

    # Reads a mapping entry's `from:` regardless of whether the entry was
    # built with string or symbol keys. Bulkrax mappings reach runtime
    # from three sources (Bulkrax.field_mappings default lambda, JSON
    # settings an app merges through HashWithIndifferentAccess, and direct
    # test construction) with inconsistent key shapes; this collapses them.
    def self.from_value(entry)
      option(entry, 'from')
    end

    # Reads one option (e.g. 'split', 'search_field') from a mapping entry
    # stored with string or symbol keys.
    def self.option(entry, name)
      return nil unless entry.is_a?(Hash)

      entry.key?(name.to_s) ? entry[name.to_s] : entry[name.to_sym]
    end

    # The mapping key whose options carry `flag` (e.g. 'source_identifier').
    # The flag counts when its key is present, whatever its value, as in
    # ApplicationParser#get_field_mapping_hash_for.
    #
    # @param mapping [Hash, nil]
    # @param flag [String, Symbol]
    # @return [String, Symbol, nil]
    def self.flagged_key(mapping, flag)
      (mapping || {}).find { |_k, v| v.is_a?(Hash) && (v.key?(flag.to_s) || v.key?(flag.to_sym)) }&.first
    end
  end
end
