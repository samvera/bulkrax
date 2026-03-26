# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvTemplate::ExplanationBuilder do
  let(:service) { instance_double('TemplateContext') }
  let(:mapping_manager) { instance_double('MappingManager') }
  let(:field_analyzer) { instance_double('FieldAnalyzer') }
  let(:column_descriptor) { instance_double(Bulkrax::CsvTemplate::ColumnDescriptor) }
  let(:split_formatter) { instance_double(Bulkrax::CsvTemplate::SplitFormatter) }

  subject(:builder) { described_class.new(service) }

  before do
    allow(service).to receive(:mapping_manager).and_return(mapping_manager)
    allow(service).to receive(:field_analyzer).and_return(field_analyzer)

    allow(Bulkrax::CsvTemplate::ColumnDescriptor).to receive(:new).and_return(column_descriptor)
    allow(Bulkrax::CsvTemplate::SplitFormatter).to receive(:new).and_return(split_formatter)
  end

  describe '#build_explanations' do
    context 'with a simple header row' do
      let(:header_row) { ['work_type', 'title', 'creator'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('work_type').and_return('work_type')
        allow(mapping_manager).to receive(:mapped_to_key).with('title').and_return('title')
        allow(mapping_manager).to receive(:mapped_to_key).with('creator').and_return('creator')

        allow(column_descriptor).to receive(:find_description_for).with('work_type')
                                                                  .and_return("The work types configured in your repository are listed below.\nIf left blank, your default work type, #{Bulkrax.default_work_type}, is used.")
        allow(column_descriptor).to receive(:find_description_for).with('title')
                                                                  .and_return(nil)
        allow(column_descriptor).to receive(:find_description_for).with('creator')
                                                                  .and_return(nil)

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])

        allow(mapping_manager).to receive(:split_value_for).and_return(nil)
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

    context 'with controlled vocabulary fields' do
      let(:header_row) { ['rights_statement', 'resource_type', 'title'] }
      let(:controlled_vocab_terms) { ['rights_statement', 'resource_type'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('rights_statement').and_return('rights_statement')
        allow(mapping_manager).to receive(:mapped_to_key).with('resource_type').and_return('resource_type')
        allow(mapping_manager).to receive(:mapped_to_key).with('title').and_return('title')

        allow(column_descriptor).to receive(:find_description_for).with('rights_statement')
                                                                  .and_return("Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen.")
        allow(column_descriptor).to receive(:find_description_for).with('resource_type').and_return(nil)
        allow(column_descriptor).to receive(:find_description_for).with('title').and_return(nil)

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return(controlled_vocab_terms)

        allow(mapping_manager).to receive(:split_value_for).with('rights_statement').and_return(nil)
        allow(mapping_manager).to receive(:split_value_for).with('resource_type').and_return(nil)
        allow(mapping_manager).to receive(:split_value_for).with('title').and_return(nil)
      end

      it 'includes controlled vocabulary text only for controlled fields' do
        result = builder.build_explanations(header_row)

        expected_rights = "Rights statement URI for the work.\nIf not included, uses the value specified on the bulk import configuration screen.\nThis property uses a controlled vocabulary."
        expect(result[0]['rights_statement']).to eq(expected_rights)

        expected_resource = "This property uses a controlled vocabulary."
        expect(result[1]['resource_type']).to eq(expected_resource)

        expect(result[2]['title']).to eq('')
      end
    end

    context 'with split value fields' do
      let(:header_row) { ['keywords', 'contributor'] }

      before do
        allow(mapping_manager).to receive(:mapped_to_key).with('keywords').and_return('keyword')
        allow(mapping_manager).to receive(:mapped_to_key).with('contributor').and_return('contributor')

        allow(column_descriptor).to receive(:find_description_for).with('keywords').and_return('Keywords or tags')
        allow(column_descriptor).to receive(:find_description_for).with('contributor').and_return('Additional contributors')

        allow(field_analyzer).to receive(:controlled_vocab_terms).and_return([])

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

    context 'with empty header row' do
      let(:header_row) { [] }

      it 'returns an empty array' do
        result = builder.build_explanations(header_row)

        expect(result).to eq([])
      end
    end
  end
end
