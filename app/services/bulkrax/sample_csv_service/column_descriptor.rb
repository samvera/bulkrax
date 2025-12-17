# frozen_string_literal: true

module Bulkrax
  # Manages column descriptions and metadata
  class SampleCsvService::ColumnDescriptor
    COLUMN_DESCRIPTIONS = {
      highlighted: [
        { "work_type" => "The work types configured in your repository are listed below.\nIf left blank, your default work type, #{Bulkrax.default_work_type}, is used." },
        { "source_identifier" => "This must be a unique identifier.\nIt can be alphanumeric with some special charaters (e.g. hyphens, colons), and URLs are also supported." },
        { "id" => "This column would optionally be included only if it is a re-import, i.e. for updating or deleting records.\nThis is a key identifier used by the system, which you wouldn't have for new imports." },
        { "rights_statement" => "Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen." }
      ],
      visibility: [
        { "visibility" => "Uses the value specified on the bulk import configuration screen if not added here.\nValid options: open, institution, restricted, embargo, lease" },
        { "embargo_release_date" => "Required for embargo (yyyy-mm-dd)" },
        { "visibility_during_embargo" => "Required for embargo" },
        { "visibility_after_embargo" => "Required for embargo" },
        { "lease_expiration_date" => "Required for lease (yyyy-mm-dd)" },
        { "visibility_during_lease" => "Required for lease" },
        { "visibility_after_lease" => "Required for lease" }
      ],
      files: [
        { "file" => "Use filenames exactly matching those in your files folder.\nZip your CSV and files folder together and attach this to your importer." },
        { "remote_files" => "Use the URLs to remote files to be attached to the work." }
      ]
    }.freeze

    def core_columns
      extract_column_names(:highlighted) + extract_column_names(:visibility)
    end

    def find_description_for(column)
      COLUMN_DESCRIPTIONS.each_value do |group|
        prop = group.find { |hash| hash.key?(column) }
        return prop[column] if prop
      end
      nil
    end

    private

    def extract_column_names(group)
      COLUMN_DESCRIPTIONS[group].map { |hash| hash.keys.first }
    end
  end
end
