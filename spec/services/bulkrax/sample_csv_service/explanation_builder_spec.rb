# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService::ExplanationBuilder do
  let(:service) { instance_double('SampleCsvService') }
  let(:mapping_manager) { instance_double('MappingManager') }
  let(:field_analyzer) { instance_double('FieldAnalyzer') }
  let(:column_descriptor) { instance_double(Bulkrax::SampleCsvService::ColumnDescriptor) }
  let(:split_formatter) { instance_double(Bulkrax::SampleCsvService::SplitFormatter) }

  subject(:builder) { described_class.new(service) }

  before do
    allow(service).to receive(:mapping_manager).and_return(mapping_manager)
    allow(service).to receive(:field_analyzer).and_return(field_analyzer)

    # Stub the dependencies that are instantiated in initialize
    allow(Bulkrax::SampleCsvService::ColumnDescriptor).to receive(:new).and_return(column_descriptor)
    allow(Bulkrax::SampleCsvService::SplitFormatter).to receive(:new).and_return(split_formatter)
  end

  describe '#build_explanations' do
    context 'with a simple header row' do
      let(:header_row) { ['work_type', 'title', 'creator'] }

      before do
        # Simulating bulkrax field mappings behavior
        allow(mapping_manager).to receive(:mapped_to_key).with('work_type').and_return('work_type')
        allow(mapping_manager).to receive(:mapped_to_key).with('title').and_return('title')
        allow(mapping_manager).to receive(:mapped_to_key).with('creator').and_return('creator')

        allow(column_descriptor).to receive(:find_description_for).with('work_type')
                                                                  .and_return("The work types configured in your repository are listed below.\nIf left blank, your default work type, #{Bulkrax.default_work_type}, is used.")
        allow(column_descriptor).to receive(:find_description_for).with('title')
                                                                  .and_return(nil) # No description defined for title
        allow(column_descriptor).to receive(:find_description_for).with('creator')
                                                                  .and_return(nil) # No description defined for creator

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])

        allow(mapping_manager).to receive(:split_value_for).and_return(nil)
        # split_formatter.format is NOT called when split_value is nil
      end

      it 'returns an array of hashes with column explanations' do
        result = builder.build_explanations(header_row)

        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
        expect(result[0]).to eq({
                                  'work_type' => "The work types configured in your repository are listed below.\nIf left blank, your default work type, #{Bulkrax.default_work_type}, is used."
                                })
        expect(result[1]).to eq({ 'title' => '' })
        expect(result[2]).to eq({ 'creator' => '' })
      end
    end

    context 'with include_first columns (special repository columns)' do
      let(:header_row) { ['source_identifier', 'id', 'rights_statement'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('source_identifier').and_return('source_identifier')
        allow(mapping_manager).to receive(:mapped_to_key).with('id').and_return('id')
        allow(mapping_manager).to receive(:mapped_to_key).with('rights_statement').and_return('rights_statement')

        allow(column_descriptor).to receive(:find_description_for).with('source_identifier')
                                                                  .and_return("This must be a unique identifier.\nIt can be alphanumeric with some special charaters (e.g. hyphens, colons), and URLs are also supported.")
        allow(column_descriptor).to receive(:find_description_for).with('id')
                                                                  .and_return("This column would optionally be included only if it is a re-import, i.e. for updating or deleting records.\nThis is a key identifier used by the system, which you wouldn't have for new imports.")
        allow(column_descriptor).to receive(:find_description_for).with('rights_statement')
                                                                  .and_return("Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen.")

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return(['rights_statement'])
        allow(mapping_manager).to receive(:split_value_for).and_return(nil)
      end

      it 'includes detailed descriptions for special columns' do
        result = builder.build_explanations(header_row)

        expect(result[0]['source_identifier']).to include("This must be a unique identifier.")
        expect(result[0]['source_identifier']).to include("alphanumeric with some special charaters")

        expect(result[1]['id']).to include("This column would optionally be included")
        expect(result[1]['id']).to include("for updating or deleting records")

        expect(result[2]['rights_statement']).to include("Rights statement URI")
        expect(result[2]['rights_statement']).to include("This property uses a controlled vocabulary.")
      end
    end

    context 'with visibility-related columns' do
      let(:header_row) { ['visibility', 'embargo_release_date', 'visibility_during_embargo'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('visibility').and_return('visibility')
        allow(mapping_manager).to receive(:mapped_to_key).with('embargo_release_date').and_return('embargo_release_date')
        allow(mapping_manager).to receive(:mapped_to_key).with('visibility_during_embargo').and_return('visibility_during_embargo')

        allow(column_descriptor).to receive(:find_description_for).with('visibility')
                                                                  .and_return("Uses the value specified on the bulk import configuration screen if not added here.\nValid options: open, institution, restricted, embargo, lease")
        allow(column_descriptor).to receive(:find_description_for).with('embargo_release_date')
                                                                  .and_return("Required for embargo (yyyy-mm-dd)")
        allow(column_descriptor).to receive(:find_description_for).with('visibility_during_embargo')
                                                                  .and_return("Required for embargo")

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return(['visibility', 'visibility_during_embargo'])
        allow(mapping_manager).to receive(:split_value_for).and_return(nil)
      end

      it 'handles visibility and embargo columns correctly' do
        result = builder.build_explanations(header_row)

        expect(result[0]['visibility']).to include("Valid options: open, institution, restricted, embargo, lease")
        expect(result[0]['visibility']).to include("This property uses a controlled vocabulary.")

        expect(result[1]['embargo_release_date']).to eq("Required for embargo (yyyy-mm-dd)")

        expect(result[2]['visibility_during_embargo']).to include("Required for embargo")
        expect(result[2]['visibility_during_embargo']).to include("This property uses a controlled vocabulary.")
      end
    end

    context 'with file-related columns' do
      let(:header_row) { ['file', 'remote_files'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('file').and_return('file')
        allow(mapping_manager).to receive(:mapped_to_key).with('remote_files').and_return('remote_files')

        allow(column_descriptor).to receive(:find_description_for).with('file')
                                                                  .and_return("Use filenames exactly matching those in your files folder.\nZip your CSV and files folder together and attach this to your importer.")
        allow(column_descriptor).to receive(:find_description_for).with('remote_files')
                                                                  .and_return("Use the URLs to remote files to be attached to the work.")

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])
        allow(mapping_manager).to receive(:split_value_for).with('file').and_return(nil)
        allow(mapping_manager).to receive(:split_value_for).with('remote_files').and_return('\|')

        # Only called when split_value is not nil
        allow(split_formatter).to receive(:format).with('\|').and_return('Split multiple values with |')
      end

      it 'handles file columns with appropriate split settings' do
        result = builder.build_explanations(header_row)

        expect(result[0]['file']).to eq("Use filenames exactly matching those in your files folder.\nZip your CSV and files folder together and attach this to your importer.")
        expect(result[0]['file']).not_to include("Property does not split.")

        expect(result[1]['remote_files']).to include("Use the URLs to remote files")
        expect(result[1]['remote_files']).to include("Split multiple values with |")
      end
    end

    context 'with controlled vocabulary fields' do
      let(:header_row) { ['rights_statement', 'resource_type', 'title'] }
      let(:controlled_vocab_terms) { ['rights_statement', 'resource_type'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('rights_statement').and_return('rights_statement')
        allow(mapping_manager).to receive(:mapped_to_key).with('resource_type').and_return('resource_type')
        allow(mapping_manager).to receive(:mapped_to_key).with('title').and_return('title')

        allow(column_descriptor).to receive(:find_description_for).with('rights_statement')
                                                                  .and_return("Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen.")
        allow(column_descriptor).to receive(:find_description_for).with('resource_type')
                                                                  .and_return(nil) # resource_type might not have a predefined description
        allow(column_descriptor).to receive(:find_description_for).with('title')
                                                                  .and_return(nil)

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return(controlled_vocab_terms)

        allow(mapping_manager).to receive(:split_value_for).with('rights_statement').and_return(nil)
        allow(mapping_manager).to receive(:split_value_for).with('resource_type').and_return(nil)
        allow(mapping_manager).to receive(:split_value_for).with('title').and_return(nil)
      end

      it 'includes controlled vocabulary text only for controlled fields' do
        result = builder.build_explanations(header_row)

        # rights_statement has both description and controlled vocab
        expected_rights = "Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen.\nThis property uses a controlled vocabulary."
        expect(result[0]['rights_statement']).to eq(expected_rights)

        # resource_type has controlled vocab but no description
        expected_resource = "This property uses a controlled vocabulary."
        expect(result[1]['resource_type']).to eq(expected_resource)

        # title has neither controlled vocab nor description (empty string)
        expect(result[2]['title']).to eq('')
      end
    end

    context 'with split value fields' do
      let(:header_row) { ['keywords', 'contributor'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('keywords').and_return('keyword')
        allow(mapping_manager).to receive(:mapped_to_key).with('contributor').and_return('contributor')

        allow(column_descriptor).to receive(:find_description_for).with('keywords')
                                                                  .and_return('Keywords or tags')
        allow(column_descriptor).to receive(:find_description_for).with('contributor')
                                                                  .and_return('Additional contributors')

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])

        # split_value_for returns escaped string delimiters from bulkrax mappings
        allow(mapping_manager).to receive(:split_value_for).with('keyword').and_return('\|')
        allow(mapping_manager).to receive(:split_value_for).with('contributor').and_return('\;')

        allow(split_formatter).to receive(:format).with('\|').and_return('Split multiple values with |')
        allow(split_formatter).to receive(:format).with('\;').and_return('Split multiple values with ;')
      end

      it 'includes split formatting information in explanations' do
        result = builder.build_explanations(header_row)

        expect(result[0]['keywords']).to eq("Keywords or tags\nSplit multiple values with |")
        expect(result[1]['contributor']).to eq("Additional contributors\nSplit multiple values with ;")
      end
    end

    context 'with all explanation components present' do
      let(:header_row) { ['genre'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('genre').and_return('genre')
        allow(column_descriptor).to receive(:find_description_for).with('genre')
                                                                  .and_return('The genre or type of work')
        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return(['genre'])
        # Escaped delimiter from bulkrax mapping split value
        allow(mapping_manager).to receive(:split_value_for).with('genre').and_return('\|\|')
        allow(split_formatter).to receive(:format).with('\|\|').and_return('Split multiple values with |, or |')
      end

      it 'combines all three components with newlines' do
        result = builder.build_explanations(header_row)

        expected = "The genre or type of work\n" \
                  "This property uses a controlled vocabulary.\n" \
                  "Split multiple values with |, or |"

        expect(result[0]['genre']).to eq(expected)
      end
    end

    context 'with fields having no description' do
      let(:header_row) { ['custom_field'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('custom_field').and_return('custom_field')
        allow(column_descriptor).to receive(:find_description_for).with('custom_field').and_return(nil)
        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])
        allow(mapping_manager).to receive(:split_value_for).with('custom_field').and_return(nil)
      end

      it 'returns only empty string when description is nil and no split' do
        result = builder.build_explanations(header_row)

        expect(result[0]['custom_field']).to eq('')
      end
    end

    context 'with mapped column names' do
      let(:header_row) { ['Title', 'Date Created'] }

      before do
        # Simulating mapping from CSV column to property name
        allow(mapping_manager).to receive(:mapped_to_key).with('Title').and_return('title')
        allow(mapping_manager).to receive(:mapped_to_key).with('Date Created').and_return('date_created')

        allow(column_descriptor).to receive(:find_description_for).with('Title')
                                                                  .and_return('The main title')
        allow(column_descriptor).to receive(:find_description_for).with('Date Created')
                                                                  .and_return('Creation date')

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])
        allow(mapping_manager).to receive(:split_value_for).with('title').and_return(nil)
        allow(mapping_manager).to receive(:split_value_for).with('date_created').and_return(nil)
      end

      it 'uses the mapped property name for controlled vocab and split checks' do
        result = builder.build_explanations(header_row)

        expect(result[0]['Title']).to eq("The main title")
        expect(result[1]['Date Created']).to eq("Creation date")
      end
    end

    context 'with empty header row' do
      let(:header_row) { [] }

      it 'returns an empty array' do
        result = builder.build_explanations(header_row)

        expect(result).to eq([])
      end
    end

    context 'with duplicate columns in header' do
      let(:header_row) { ['title', 'title'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('title').and_return('title')
        allow(column_descriptor).to receive(:find_description_for).with('title')
                                                                  .and_return('The title of the work')
        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])
        allow(mapping_manager).to receive(:split_value_for).with('title').and_return(nil)
      end

      it 'processes each column independently' do
        result = builder.build_explanations(header_row)

        expect(result.length).to eq(2)
        expect(result[0]).to eq({ 'title' => "The title of the work" })
        expect(result[1]).to eq({ 'title' => "The title of the work" })
      end
    end

    context 'when only controlled vocab component is present' do
      let(:header_row) { ['resource_type'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('resource_type').and_return('resource_type')
        allow(column_descriptor).to receive(:find_description_for).with('resource_type').and_return(nil)
        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return(['resource_type', 'rights_statement', 'audience', 'education_level', 'license', 'learning_resource_type'])
        allow(mapping_manager).to receive(:split_value_for).with('resource_type').and_return(nil)
      end

      it 'returns controlled vocab text only' do
        result = builder.build_explanations(header_row)

        expected = "This property uses a controlled vocabulary."
        expect(result[0]['resource_type']).to eq(expected)
      end
    end

    context 'when only split component is present' do
      let(:header_row) { ['tags'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('tags').and_return('tag')
        allow(column_descriptor).to receive(:find_description_for).with('tags').and_return(nil)
        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])
        allow(mapping_manager).to receive(:split_value_for).with('tag').and_return('\|')
        allow(split_formatter).to receive(:format).with('\|').and_return('Split multiple values with |')
      end

      it 'returns only the split text' do
        result = builder.build_explanations(header_row)

        expect(result[0]['tags']).to eq('Split multiple values with |')
      end
    end

    context 'with common split delimiters' do
      let(:header_row) { ['subjects', 'identifiers', 'notes'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('subjects').and_return('subject')
        allow(mapping_manager).to receive(:mapped_to_key).with('identifiers').and_return('identifier')
        allow(mapping_manager).to receive(:mapped_to_key).with('notes').and_return('note')

        allow(column_descriptor).to receive(:find_description_for).with('subjects').and_return('Subject terms')
        allow(column_descriptor).to receive(:find_description_for).with('identifiers').and_return('Identifiers')
        allow(column_descriptor).to receive(:find_description_for).with('notes').and_return('Notes')

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])

        # Common delimiters in the system
        allow(mapping_manager).to receive(:split_value_for).with('subject').and_return('\;')
        allow(mapping_manager).to receive(:split_value_for).with('identifier').and_return('\|')
        allow(mapping_manager).to receive(:split_value_for).with('note').and_return('\:')

        allow(split_formatter).to receive(:format).with('\;').and_return('Split multiple values with ;')
        allow(split_formatter).to receive(:format).with('\|').and_return('Split multiple values with |')
        allow(split_formatter).to receive(:format).with('\:').and_return('Split multiple values with :')
      end

      it 'handles different delimiter types correctly' do
        result = builder.build_explanations(header_row)

        expect(result[0]['subjects']).to eq("Subject terms\nSplit multiple values with ;")
        expect(result[1]['identifiers']).to eq("Identifiers\nSplit multiple values with |")
        expect(result[2]['notes']).to eq("Notes\nSplit multiple values with :")
      end
    end

    context 'error handling' do
      let(:header_row) { ['problematic_column'] }

      context 'when mapping_manager.mapped_to_key raises an error' do
        before do
          allow(mapping_manager).to receive(:mapped_to_key).and_raise(StandardError, 'Mapping error')
        end

        it 'allows the error to bubble up' do
          expect { builder.build_explanations(header_row) }.to raise_error(StandardError, 'Mapping error')
        end
      end

      context 'when column_descriptor.find_description_for raises an error' do
        before do
          allow(mapping_manager).to receive(:mapped_to_key).with('problematic_column')
                                                           .and_return('problematic_column')
          allow(column_descriptor).to receive(:find_description_for).and_raise(StandardError, 'Description error')
        end

        it 'allows the error to bubble up' do
          expect { builder.build_explanations(header_row) }.to raise_error(StandardError, 'Description error')
        end
      end

      context 'when split_formatter.format raises an error' do
        before do
          allow(mapping_manager).to receive(:mapped_to_key).with('problematic_column')
                                                           .and_return('problematic_column')
          allow(column_descriptor).to receive(:find_description_for).with('problematic_column').and_return(nil)
          allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])
          allow(mapping_manager).to receive(:split_value_for).with('problematic_column').and_return('\|')
          allow(split_formatter).to receive(:format).with('\|').and_raise(StandardError, 'Format error')
        end

        it 'allows the error to bubble up' do
          expect { builder.build_explanations(header_row) }.to raise_error(StandardError, 'Format error')
        end
      end
    end
  end
end
