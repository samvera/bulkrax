module Bulkrax
  module ImporterV2
    extend ActiveSupport::Concern

    # trigger form to allow upload
    def new_v2

    end

    # validate and process uploaded files located at 'import_file_path'
    def validate_v2
      # - validate the csv headers
      # - read the zip file to make sure it is not malformed?
      # -> future will check that all files are present and accounted for, but this is a start
      return unless @importer.valid_import?
      true
    end

    def create_v2
      # remove spaces from filenames
      # create the directory expected by importer_job and create files there in files directory as expected by importer_job
    end
  end
end
