# frozen_string_literal: true

module Bulkrax
  # Builds CSV content
  class SampleCsvService::CsvBuilder
    IGNORED_PROPERTIES = %w[
      admin_set_id alternate_ids arkivo_checksum
      bulkrax_identifier
      collection_type_gid contexts created_at
      date_modified date_uploaded depositor
      embargo embargo_id
      file_ids
      has_model head
      internal_resource is_child
      lease lease_id
      member_ids member_of_collection_ids modified_date
      new_record
      on_behalf_of owner proxy_depositor
      rendering_ids representative_id
      schema_version split_from_pdf_id state tail
      thumbnail_id
      updated_at
    ].freeze

    def initialize(service)
      @service = service
      @column_builder = SampleCsvService::ColumnBuilder.new(service)
      @row_builder = SampleCsvService::RowBuilder.new(service)
      @header_row = nil
      @required_headings = []
    end

    def write_to_file(file_path)
      CSV.open(file_path, "w") { |csv| write_rows(csv) }
    end

    def generate_string
      CSV.generate { |csv| write_rows(csv) }
    end

    private

    def write_rows(csv)
      csv_rows.each { |row| csv << row }
    end

    def csv_rows
      @header_row = fill_header_row
      rows = [
        @header_row,
        @row_builder.build_explanation_row(@header_row),
        *@row_builder.build_model_rows(@header_row)
      ]
      remove_empty_columns(rows)
    end

    def fill_header_row
      @required_headings = @column_builder.required_columns
      all_columns = @column_builder.all_columns
      filtered = all_columns - IGNORED_PROPERTIES
      @required_headings = @column_builder.required_columns & filtered
      filtered
    end

    def remove_empty_columns(rows)
      return rows if rows.empty?

      columns = rows.transpose
      non_empty_columns = columns.select { |col| keep_column?(col) }
      non_empty_columns.transpose
    end

    def keep_column?(column)
      heading = column[0]
      return true if @required_headings.include?(heading)

      # Check if any data row has content
      column[2..-1].any? { |value| !value.nil? && value != "" && value != "---" }
    end
  end
end
