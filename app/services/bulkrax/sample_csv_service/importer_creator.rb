# frozen_string_literal: true

module Bulkrax
  class SampleCsvService::ImporterCreator
    def self.create(file_path)
      Bulkrax::Importer.create(
        name: "Sample CSV #{Time.now.utc.to_date}",
        admin_set_id: Hyrax::AdminSetCreateService.find_or_create_default_admin_set.id,
        user_id: User.find_by(email: 'admin@example.com').id,
        frequency: 'PT0S',
        parser_klass: 'Bulkrax::CsvParser',
        parser_fields: parser_fields(file_path)
      )
    end

    def self.parser_fields(file_path)
      {
        'visibility' => 'open',
        'rights_statement' => '',
        'override_rights_statement' => '0',
        'file_style' => 'Specify a Path on the Server',
        'import_file_path' => file_path,
        'update_files' => false
      }
    end
  end
end
