# frozen_string_literal: true

module Bulkrax
  # Decides where each zip entry lands under `importer_unzip_path/` when a
  # user uploads a CSV+zip (or a zip containing the CSV) through the guided
  # importer. The plan is pure metadata — no IO, no extraction — so both
  # the import-time extraction path and the validator can rely on the
  # same placement rules.
  #
  # The two call sites are:
  #
  # * {Bulkrax::CsvParser#unzip_with_primary_csv} /
  #   {#unzip_attachments_only} — execute the plan by writing each entry
  #   to its planned destination.
  # * {Bulkrax::CsvRow::FileReference} (validator) — compares
  #   `record[:file]` paths against the set of paths the plan will make
  #   available under `files/`.
  #
  # Modes:
  #
  # * `:primary_csv` — zip contains the CSV. The CSV at the shallowest
  #   directory depth is the primary; it extracts to the root of the
  #   destination, everything else goes under `files/` preserving its
  #   path relative to the primary CSV's directory.
  # * `:attachments_only` — zip accompanies a separately-uploaded CSV.
  #   Every entry lands under `files/`. If every entry shares a single
  #   top-level wrapper directory, that wrapper is stripped.
  module ZipPlacementPlanner
    # The output of a planning run.
    #
    # @!attribute primary_csv_entry
    #   @return [Zip::Entry, nil] the chosen primary CSV (nil in
    #     `:attachments_only` mode)
    # @!attribute placements
    #   @return [Hash{Zip::Entry => String}] every entry keyed to its
    #     destination path relative to the unzip dest dir
    # @!attribute available_paths
    #   @return [Array<String>] the relative paths that will exist under
    #     `files/` after extraction. Does not include the primary CSV.
    Plan = Struct.new(:primary_csv_entry, :placements, :available_paths, keyword_init: true)

    # Builds a placement plan for a list of zip entries.
    #
    # @param entries [Array<Zip::Entry>] entries already filtered to real
    #   files (no directories, no macOS junk) and validated for Zip Slip
    #   safety — see {Bulkrax::ApplicationParser#real_zip_entries}.
    # @param mode [Symbol] `:primary_csv` or `:attachments_only`
    # @return [Plan]
    # @raise [Bulkrax::UnzipError] in `:primary_csv` mode when no CSV is
    #   present or multiple CSVs share the shallowest level.
    def self.plan(entries, mode:)
      case mode
      when :primary_csv then plan_with_primary_csv(entries)
      when :attachments_only then plan_attachments_only(entries)
      else raise ArgumentError, "Unknown mode: #{mode.inspect}"
      end
    end

    def self.plan_with_primary_csv(entries)
      primary = select_primary_csv!(entries)
      primary_dir = File.dirname(primary.name)
      placements = {}
      entries.each do |entry|
        placements[entry] = if entry == primary
                              File.basename(entry.name)
                            else
                              File.join('files', relative_to(primary_dir, entry.name))
                            end
      end
      Plan.new(
        primary_csv_entry: primary,
        placements: placements,
        available_paths: paths_under_files(placements)
      )
    end
    private_class_method :plan_with_primary_csv

    def self.plan_attachments_only(entries)
      wrapper = single_top_level_wrapper(entries)
      placements = {}
      entries.each do |entry|
        relative = wrapper ? entry.name.delete_prefix("#{wrapper}/") : entry.name
        next if relative.empty?

        placements[entry] = File.join('files', relative)
      end
      Plan.new(
        primary_csv_entry: nil,
        placements: placements,
        available_paths: paths_under_files(placements)
      )
    end
    private_class_method :plan_attachments_only

    # Picks the single primary CSV, enforcing the shallowest-level rule.
    def self.select_primary_csv!(entries)
      csvs = entries.select { |e| e.name.end_with?('.csv') }
      raise Bulkrax::UnzipError, I18n.t('bulkrax.importer.unzip.errors.no_csv') if csvs.empty?

      by_depth = csvs.group_by { |e| e.name.count('/') }
      shallowest = by_depth[by_depth.keys.min]

      raise Bulkrax::UnzipError, I18n.t('bulkrax.importer.unzip.errors.multiple_csv') if shallowest.size > 1

      shallowest.first
    end
    private_class_method :select_primary_csv!

    # If every entry shares a single top-level directory, returns that
    # directory name; otherwise nil.
    def self.single_top_level_wrapper(entries)
      tops = entries.map { |e| e.name.split('/').first }.uniq
      return nil unless tops.size == 1
      # A single top segment that is itself a file (no directory) isn't a wrapper.
      return nil if entries.any? { |e| e.name == tops.first }

      tops.first
    end
    private_class_method :single_top_level_wrapper

    # Returns `path` with `prefix/` removed from the front, if present,
    # and a leading `files/` segment also stripped so callers can join
    # under `files/` without doubling when the zip already uses that
    # convention.
    def self.relative_to(prefix, path)
      remaining = prefix == '.' || prefix.empty? ? path : path.delete_prefix("#{prefix}/")
      remaining.delete_prefix('files/')
    end
    private_class_method :relative_to

    def self.paths_under_files(placements)
      placements.values.filter_map { |rel| rel.delete_prefix('files/') if rel.start_with?('files/') }
    end
    private_class_method :paths_under_files
  end
end
