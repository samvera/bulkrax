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

      context 'file-column validation parity with import' do
        before do
          stub_bulkrax_models
          allow(Bulkrax).to receive(:field_mappings).and_return(
            'Bulkrax::CsvParser' => {
              'title' => { 'from' => ['title'] },
              'model' => { 'from' => ['model'] },
              'parents' => { 'from' => ['parents'], 'related_parents_field_mapping' => true },
              'file' => { 'from' => %w[item file], 'split' => '\\|' },
              'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
            }
          )
        end

        let(:csv_upload) do
          t = Tempfile.new(['data', '.csv'])
          t.write(csv_content)
          t.flush
          Rack::Test::UploadedFile.new(t.path, 'text/csv', original_filename: 'data.csv')
        end

        let(:zip_upload) do
          t = Tempfile.new(['upload', '.zip'])
          Zip::File.open(t.path, create: true) do |zip|
            present_in_zip.each { |name| zip.get_output_stream(name) { |f| f.write('fake') } }
          end
          Rack::Test::UploadedFile.new(t.path, 'application/zip', original_filename: 'upload.zip')
        end

        shared_examples 'reports the missing file' do |missing_name|
          it "reports #{missing_name} as missing in the JSON response" do
            post_validate(importer: { parser_fields: { files: [csv_upload, zip_upload] } })

            expect(response).to have_http_status(:ok)
            row_errors = json_response[:rowErrors] || []
            expect(row_errors).to include(
              a_hash_including(
                category: 'missing_file_reference',
                column: 'file',
                value: missing_name
              )
            )
          end
        end

        context 'when the CSV uses the canonical `file` column' do
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,file
              work1,Work 1,GenericWork,present.jpg
              work2,Work 2,GenericWork,missing.jpg
            CSV
          end
          let(:present_in_zip) { %w[present.jpg] }

          include_examples 'reports the missing file', 'missing.jpg'
        end

        context 'when the CSV uses an aliased column (`item` only)' do
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,item
              work1,Work 1,GenericWork,present.jpg
              work2,Work 2,GenericWork,missing.jpg
            CSV
          end
          let(:present_in_zip) { %w[present.jpg] }

          include_examples 'reports the missing file', 'missing.jpg'
        end

        context 'when `from:` lists the canonical name first and the CSV uses only the alias' do
          before do
            allow(Bulkrax).to receive(:field_mappings).and_return(
              'Bulkrax::CsvParser' => {
                'title' => { 'from' => ['title'] },
                'model' => { 'from' => ['model'] },
                'parents' => { 'from' => ['parents'], 'related_parents_field_mapping' => true },
                'file' => { 'from' => %w[file item], 'split' => '\\|' },
                'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
              }
            )
          end
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,item
              work1,Work 1,GenericWork,present.jpg
              work2,Work 2,GenericWork,missing.jpg
            CSV
          end
          let(:present_in_zip) { %w[present.jpg] }

          include_examples 'reports the missing file', 'missing.jpg'
        end

        context 'when a single cell lists multiple files separated by `|`' do
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,file
              work1,Work 1,GenericWork,present.jpg|missing.jpg
            CSV
          end
          let(:present_in_zip) { %w[present.jpg] }

          include_examples 'reports the missing file', 'missing.jpg'
        end

        context 'when the mapping configures `split:` as a serialised Regexp' do
          before do
            allow(Bulkrax).to receive(:field_mappings).and_return(
              'Bulkrax::CsvParser' => {
                'title' => { 'from' => ['title'] },
                'model' => { 'from' => ['model'] },
                'parents' => { 'from' => ['parents'], 'related_parents_field_mapping' => true },
                'file' => { 'from' => %w[item file], 'split' => '(?-mix:\\s*[;|]\\s*)' },
                'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
              }
            )
          end
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,file
              work1,Work 1,GenericWork,present.jpg | missing.jpg
            CSV
          end
          let(:present_in_zip) { %w[present.jpg] }

          include_examples 'reports the missing file', 'missing.jpg'
        end
      end

      # Path-aware cases that the basename-only FileValidator silently
      # passes, but that would fail at import time. Validation should fail
      # by emitting per-row file errors (category: 'missing_file_reference').
      context 'path-aware file validation' do
        before { stub_bulkrax_models }

        let(:csv_upload) do
          t = Tempfile.new(['data', '.csv'])
          t.write(csv_content)
          t.flush
          Rack::Test::UploadedFile.new(t.path, 'text/csv', original_filename: 'data.csv')
        end

        # Build a zip whose entry names are `zip_entries` verbatim.
        let(:zip_upload) do
          t = Tempfile.new(['upload', '.zip'])
          Zip::File.open(t.path, create: true) do |zip|
            zip_entries.each { |name| zip.get_output_stream(name) { |f| f.write('fake') } }
          end
          Rack::Test::UploadedFile.new(t.path, 'application/zip', original_filename: 'upload.zip')
        end

        shared_examples 'per-row error for the referenced path' do |missing_path|
          it "emits a missing_file_reference row warning for #{missing_path}" do
            post_validate(importer: { parser_fields: { files: [csv_upload, zip_upload] } })

            expect(response).to have_http_status(:ok)
            # Missing files are warnings, not errors — the file may still
            # exist on the server at import time.
            expect(json_response[:hasWarnings]).to eq(true)
            row_errors = json_response[:rowErrors] || []
            expect(row_errors).to include(
              a_hash_including(
                severity: 'warning',
                category: 'missing_file_reference',
                column: 'file',
                value: missing_path
              )
            )
          end
        end

        context 'subdirectory mismatch' do
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,file
              w1,W1,GenericWork,subdir_a/foo.jpg
            CSV
          end
          let(:zip_entries) { %w[files/subdir_b/foo.jpg] }

          include_examples 'per-row error for the referenced path', 'subdir_a/foo.jpg'
        end

        context 'root/nested mismatch' do
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,file
              w1,W1,GenericWork,foo.jpg
            CSV
          end
          let(:zip_entries) { %w[files/deep/nested/foo.jpg] }

          include_examples 'per-row error for the referenced path', 'foo.jpg'
        end

        context 'duplicate basenames at different depths' do
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,file
              w1,W1,GenericWork,foo.jpg
            CSV
          end
          let(:zip_entries) { %w[files/dir_a/foo.jpg files/dir_b/foo.jpg] }

          include_examples 'per-row error for the referenced path', 'foo.jpg'
        end

        context 'exact-path match (regression guard)' do
          let(:csv_content) do
            <<~CSV
              source_identifier,title,model,file
              w1,W1,GenericWork,subdir/foo.jpg
            CSV
          end
          let(:zip_entries) { %w[files/subdir/foo.jpg] }

          it 'emits no file-reference row errors' do
            post_validate(importer: { parser_fields: { files: [csv_upload, zip_upload] } })
            row_errors = json_response[:rowErrors] || []
            expect(row_errors).to all(satisfy { |e| e[:category] != 'missing_file_reference' })
          end
        end
      end

      # When a tenant aliases a flag-resolved column (parents/children/
      # source_identifier) and the CSV uses the alias, the validator must
      # read the aliased column. Previously the validator picked the
      # first `from:` entry blindly, so a CSV with header `parents` but
      # mapping `from: ['collection', 'parents']` looked at `:collection`
      # — every row's parent came out nil and parent-reference validation
      # didn't fire.
      context 'flag-resolved column aliasing parity with import' do
        before { stub_bulkrax_models }

        let(:csv_upload) do
          t = Tempfile.new(['data', '.csv'])
          t.write(csv_content)
          t.flush
          Rack::Test::UploadedFile.new(t.path, 'text/csv', original_filename: 'data.csv')
        end

        context "when the `parents` mapping aliases as `from: ['collection', 'parents']`" do
          before do
            allow(Bulkrax).to receive(:field_mappings).and_return(
              'Bulkrax::CsvParser' => {
                'title' => { 'from' => ['title'] },
                'model' => { 'from' => ['model'] },
                'parents' => { 'from' => %w[collection parents], 'related_parents_field_mapping' => true },
                'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
              }
            )
          end

          context 'and the CSV uses the canonical `parents` column' do
            let(:csv_content) do
              <<~CSV
                source_identifier,title,model,parents
                w1,Work 1,GenericWork,nonexistent_parent
              CSV
            end

            it 'reports the unresolvable parent' do
              post_validate(importer: { parser_fields: { files: [csv_upload] } })
              row_errors = json_response[:rowErrors] || []
              expect(row_errors).to include(
                a_hash_including(category: 'invalid_parent_reference', value: 'nonexistent_parent')
              )
            end
          end

          context 'and the CSV uses the aliased `collection` column' do
            let(:csv_content) do
              <<~CSV
                source_identifier,title,model,collection
                w1,Work 1,GenericWork,nonexistent_parent
              CSV
            end

            it 'reports the unresolvable parent' do
              post_validate(importer: { parser_fields: { files: [csv_upload] } })
              row_errors = json_response[:rowErrors] || []
              expect(row_errors).to include(
                a_hash_including(category: 'invalid_parent_reference', value: 'nonexistent_parent')
              )
            end
          end
        end

        context "when the `source_identifier` mapping aliases as `from: ['external_id', 'source_identifier']`" do
          before do
            allow(Bulkrax).to receive(:field_mappings).and_return(
              'Bulkrax::CsvParser' => {
                'title' => { 'from' => ['title'] },
                'model' => { 'from' => ['model'] },
                'parents' => { 'from' => ['parents'], 'related_parents_field_mapping' => true },
                'source_identifier' => { 'from' => %w[external_id source_identifier], 'source_identifier' => true }
              }
            )
          end

          let(:csv_content) do
            <<~CSV
              external_id,title,model
              w1,Work 1,GenericWork
              w1,Work 2,GenericWork
            CSV
          end

          it 'reads source_identifier from the aliased column and detects duplicates' do
            post_validate(importer: { parser_fields: { files: [csv_upload] } })
            row_errors = json_response[:rowErrors] || []
            expect(row_errors).to include(
              a_hash_including(category: 'duplicate_source_identifier', value: 'w1')
            )
          end
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
