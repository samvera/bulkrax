# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe GuidedImportsController, type: :controller do
    routes { Bulkrax::Engine.routes }

    let(:current_ability) { instance_double(Ability) }

    let(:user) { FactoryBot.create(:user) }

    before do
      user # ensure user is created
      module Bulkrax::Auth
        def authenticate_user!
          @current_user = User.first
          true
        end

        def current_user
          @current_user
        end
      end
      described_class.prepend Bulkrax::Auth
      allow(current_ability).to receive(:can_import_works?).and_return(true)
      allow(controller).to receive(:current_ability).and_return(current_ability)
    end

    # -------------------------------------------------------------------------
    # POST #validate
    # -------------------------------------------------------------------------

    describe 'POST #validate' do
      def post_validate(params)
        post :validate, params: params, format: :json
      end

      def json_response
        JSON.parse(response.body, symbolize_names: true)
      end

      let(:validation_success) do
        {
          headers: ['model', 'source_identifier', 'title'],
          missingRequired: [], unrecognized: {}, rowCount: 4,
          isValid: true, hasWarnings: false,
          collections: [], works: [], fileSets: [],
          totalItems: 0, fileReferences: 0, missingFiles: [], foundFiles: 0, zipIncluded: false
        }
      end

      context 'with a CSV uploaded directly' do
        let(:csv_upload) { fixture_file_upload('spec/fixtures/csv/good.csv', 'text/csv') }

        before { allow(Bulkrax::CsvParser).to receive(:validate_csv).and_return(validation_success) }

        it 'calls CsvParser.validate_csv and returns a successful response' do
          post_validate(importer: { parser_fields: { files: [csv_upload] } })
          expect(response).to have_http_status(:ok)
          expect(json_response[:isValid]).to eq(true)
        end
      end

      context 'with a file path that exists' do
        before { allow(Bulkrax::CsvParser).to receive(:validate_csv).and_return(validation_success) }

        it 'calls CsvParser.validate_csv and returns a successful response' do
          post_validate(importer: { parser_fields: { import_file_path: 'spec/fixtures/csv/good.csv' } })
          expect(response).to have_http_status(:ok)
          expect(json_response[:isValid]).to eq(true)
        end
      end

      context 'with a ZIP file containing a valid CSV' do
        let(:zip_upload) do
          t = Tempfile.new(['upload', '.zip'])
          Zip::File.open(t.path, create: true) do |zip|
            zip.get_output_stream('data.csv') { |f| f.write("model,source_identifier,title\nGenericWork,1,Test\n") }
          end
          Rack::Test::UploadedFile.new(t.path, 'application/zip', original_filename: 'upload.zip')
        end

        before { allow(Bulkrax::CsvParser).to receive(:validate_csv).and_return(validation_success) }

        it 'extracts the CSV and returns a successful response' do
          post_validate(importer: { parser_fields: { files: [zip_upload] } })
          expect(response).to have_http_status(:ok)
          expect(json_response[:isValid]).to eq(true)
        end
      end

      context 'with no files uploaded' do
        it 'returns an error response' do
          post_validate(importer: { parser_fields: { files: [] } })
          expect(response).to have_http_status(:ok)
          expect(json_response.dig(:messages, :validationStatus, :severity)).to eq('error')
        end
      end

      context 'with a file path that does not exist' do
        it 'returns an error response' do
          post_validate(importer: { parser_fields: { import_file_path: '/nonexistent/path/data.csv' } })
          expect(response).to have_http_status(:ok)
          expect(json_response.dig(:messages, :validationStatus, :severity)).to eq('error')
        end
      end

      context 'with a ZIP containing no CSV' do
        let(:zip_upload) do
          t = Tempfile.new(['upload', '.zip'])
          Zip::File.open(t.path, create: true) { |zip| zip.get_output_stream('readme.txt') { |f| f.write('nothing') } }
          Rack::Test::UploadedFile.new(t.path, 'application/zip', original_filename: 'upload.zip')
        end

        it 'returns an error response' do
          post_validate(importer: { parser_fields: { files: [zip_upload] } })
          expect(response).to have_http_status(:ok)
          expect(json_response.dig(:messages, :validationStatus, :severity)).to eq('error')
        end
      end

      context 'with a non-CSV, non-ZIP file' do
        let(:png_upload) do
          t = Tempfile.new(['image', '.png'])
          t.write('fake image data')
          t.flush
          Rack::Test::UploadedFile.new(t.path, 'image/png', original_filename: 'image.png')
        end

        it 'returns an error response' do
          post_validate(importer: { parser_fields: { files: [png_upload] } })
          expect(response).to have_http_status(:ok)
          expect(json_response.dig(:messages, :validationStatus, :severity)).to eq('error')
        end
      end
    end

    # -------------------------------------------------------------------------
    # POST #create
    # -------------------------------------------------------------------------

    describe 'POST #create' do
      let(:csv_upload) { fixture_file_upload('spec/fixtures/csv/good.csv', 'text/csv') }
      let(:valid_importer_params) do
        {
          name: 'Test Guided Import',
          admin_set_id: 'admin_set/default',
          limit: '',
          parser_fields: { visibility: 'open', rights_statement: '', override_rights_statement: '0', file_style: '' }
        }
      end

      def post_create(extra_parser_fields = {})
        post :create, params: {
          importer: valid_importer_params.merge(
            parser_fields: valid_importer_params[:parser_fields].merge(files: [csv_upload]).merge(extra_parser_fields)
          )
        }
      end

      before { allow(Bulkrax::ImporterJob).to receive(:perform_later) }

      context 'with a valid CSV upload' do
        it 'creates an importer' do
          expect { post_create }.to change(Importer, :count).by(1)
        end

        it 'enqueues an import job' do
          post_create
          expect(Bulkrax::ImporterJob).to have_received(:perform_later)
        end

        it 'redirects to importers path' do
          post_create
          expect(response).to redirect_to(importers_path)
        end
      end

      context 'with override_rights_statement in parser_fields' do
        it 'permits the parameter and saves it on the importer' do
          post_create(override_rights_statement: '1')
          expect(Importer.last.parser_fields['override_rights_statement']).to eq('1')
        end
      end

      context 'with invalid importer params' do
        it 're-renders the new template' do
          post :create, params: { importer: { name: '' } }
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'does not enqueue a job' do
          post :create, params: { importer: { name: '' } }
          expect(Bulkrax::ImporterJob).not_to have_received(:perform_later)
        end
      end

      context 'when uploaded_files param is present but resolves to nothing' do
        it 'returns unprocessable entity' do
          allow(controller).to receive(:resolve_create_files).and_return([])
          post :create, params: { uploaded_files: ['999'], importer: valid_importer_params }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'with JSON format' do
        it 'returns a created JSON response on success' do
          post :create, params: {
            importer: valid_importer_params.merge(
              parser_fields: valid_importer_params[:parser_fields].merge(files: [csv_upload])
            )
          }, format: :json
          expect(response).to have_http_status(:created)
          expect(JSON.parse(response.body)['success']).to eq(true)
        end
      end
    end
  end
end
