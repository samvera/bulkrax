# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Bulkrax::SampleCsvService do
  let(:service) { described_class.new(model_name: model_name) }
  let(:model_name) { nil }

  before do
    # Mock Hyrax configuration
    allow(Hyrax).to receive(:config).and_return(
      double(curation_concerns: [GenericWorkResource, ImageResource, EtdResource, OerResource])
    )
    allow(Bulkrax).to receive(:default_work_type).and_return('GenericWorkResource')
    allow(Bulkrax).to receive(:collection_model_class).and_return(CollectionResource)
    allow(Bulkrax).to receive(:file_model_class).and_return(Hyrax::FileSet)

    # Mock field mappings
    allow(Bulkrax).to receive(:field_mappings).and_return(
      "Bulkrax::CsvParser" => {
        'abstract' => { from: ['abstract'], split: true },
        "title" => { "from" => ["xtitle"], "split" => /\s*[|]\s*/ },
        "creator" => { "from" => ["xcreator"], "split" => true },
        "description" => { "from" => ["xdescription"], "split" => true },
        "rights_statement" => { "from" => ["rights", "rights_statement"], "split" => "\\|", "generated" => true },
        "file" => { "from" => ["xlocalfiles"], "split" => /\s*[|]\s*/ },
        "remote_files" => { "from" => ["xrefs"], "split" => /\s*[|]\s*/ },
        "children" => { "from" => ["xchildren"], "related_children_field_mapping" => true },
        "parents" => { "from" => ["xparents"], "related_parents_field_mapping" => true },
        "visibility" => { "from" => ["visibility"] },
        "source_identifier" => { "from" => ["source_identifier"], "source_identifier" => true }
      }
    )

    # Mock multi-value split pattern
    allow(Bulkrax).to receive(:multi_value_element_split_on).and_return(/\s*[|]\s*/)
  end

  describe '.call' do
    context 'when Hyrax is not defined' do
      before { hide_const("Hyrax") }

      it 'raises NameError' do
        expect { described_class.call }.to raise_error(NameError, "Hyrax is not defined")
      end
    end

    context 'when Hyrax is defined' do
      it 'returns a CSV file when output is file' do
        allow_any_instance_of(described_class).to receive(:to_file).and_return('file_path')
        expect(described_class.call(output: 'file')).to eq('file_path')
      end

      it 'returns a CSV string when output is csv_string' do
        allow_any_instance_of(described_class).to receive(:to_csv_string).and_return('csv_content')
        expect(described_class.call(output: 'csv_string')).to eq('csv_content')
      end
    end
  end

  describe '#initialize' do
    context 'with nil model_name' do
      it 'sets @all_models to empty array' do
        expect(service.instance_variable_get(:@all_models)).to eq([])
      end
    end

    context 'with "all" model_name' do
      let(:model_name) { 'all' }

      it 'loads all configured models' do
        models = service.instance_variable_get(:@all_models)
        expect(models).to include('GenericWorkResource', 'Image', 'Etd', 'Oer')
        expect(models).to include('CollectionResource', 'Hyrax::FileSet')
      end
    end

    context 'with specific model_name' do
      let(:model_name) { 'GenericWorkResource' }

      before do
        allow('GenericWorkResource').to receive(:constantize).and_return(GenericWorkResource)
      end

      it 'sets @all_models to contain only that model' do
        expect(service.instance_variable_get(:@all_models)).to eq(['GenericWorkResource'])
      end
    end

    it 'filters out generated fields from mappings except rights_statement' do
      mappings = service.instance_variable_get(:@mappings)
      expect(mappings).to have_key('rights_statement')
      # Add more expectations based on your actual generated fields
    end
  end

  describe '#to_file' do
    let(:model_name) { 'GenericWorkResource' }
    let(:file_path) { Rails.root.join('tmp', 'test.csv') }

    before do
      allow(service).to receive(:csv_rows).and_return([
        ['work_type', 'source_identifier', 'title'],
        ['Description 1', 'Description 2', 'Description 3'],
        ['GenericWorkResource', 'Required', 'Required']
      ])
    end

    it 'creates a CSV file at the specified path' do
      expect(CSV).to receive(:open).with(file_path, "w")
      service.to_file(file_path: file_path)
    end

    it 'uses default path when none provided' do
      expect(CSV).to receive(:open).with(anything, "w")
      service.to_file
    end
  end

  describe '#to_csv_string' do
    before do
      allow(service).to receive(:csv_rows).and_return([
        ['work_type', 'source_identifier'],
        ['Type description', 'ID description'],
        ['GenericWorkResource', 'Required']
      ])
    end

    it 'returns a CSV string' do
      result = service.to_csv_string
      expect(result).to be_a(String)
      expect(result).to include('work_type,source_identifier')
      expect(result).to include('GenericWork,Required')
    end
  end

  describe '#to_importer' do
    let(:admin_set) { double(id: 'admin-set-123') }
    let(:user) { double(id: 1) }

    before do
      allow(Hyrax::AdminSetCreateService).to receive(:find_or_create_default_admin_set).and_return(admin_set)
      allow(User).to receive(:find_by).with(email: 'admin@example.com').and_return(user)
      allow(service).to receive(:to_file)
    end

    it 'creates a Bulkrax::Importer' do
      expect(Bulkrax::Importer).to receive(:create).with(
        hash_including(
          name: match(/Sample CSV/),
          admin_set_id: 'admin-set-123',
          user_id: 1,
          parser_klass: 'Bulkrax::CsvParser'
        )
      )
      service.to_importer
    end
  end

  describe 'private methods' do
    describe '#csv_rows' do
      let(:model_name) { 'GenericWorkResource' }

      before do
        allow(service).to receive(:fill_header_row).and_return(['work_type', 'title'])
        allow(service).to receive(:property_explanations).and_return([
          { 'work_type' => 'Type description' },
          { 'title' => 'Title description' }
        ])
        allow(service).to receive(:model_breakdown).and_return(['GenericWorkResource', 'Required'])
        allow(service).to receive(:remove_empty_columns) { |rows| rows }
      end

      it 'generates header, explanation, and model rows' do
        rows = service.send(:csv_rows)
        expect(rows).to have_exactly(3).items
        expect(rows[0]).to eq(['work_type', 'title'])
        expect(rows[1]).to include('Type description', 'Title description')
      end
    end

    describe '#fill_header_row' do
      let(:model_name) { 'all' }

      it 'returns headers in correct order' do
        header = service.send(:fill_header_row)

        # Check that highlighted properties come first
        expect(header[0]).to eq('work_type')
        expect(header[1]).to eq('source_identifier')

        # Check that visibility properties follow
        expect(header).to include('visibility', 'embargo_release_date')

        # Check that relationship properties are included
        expect(header).to include('xchildren', 'xparents')

        # Check that file properties are included
        expect(header).to include('xlocalfiles', 'xrefs')
      end

      it 'excludes ignored properties' do
        header = service.send(:fill_header_row)
        described_class::IGNORED_PROPERTIES.each do |ignored|
          expect(header).not_to include(ignored)
        end
      end
    end

    describe '#mapped_to_key' do
      it 'returns the key for a mapped column' do
        expect(service.send(:mapped_to_key, 'xtitle')).to eq('title')
        expect(service.send(:mapped_to_key, 'xcreator')).to eq('creator')
      end

      it 'returns the original column if no mapping exists' do
        expect(service.send(:mapped_to_key, 'unmapped_field')).to eq('unmapped_field')
      end
    end

    describe '#key_to_mapped_column' do
      it 'returns the first "from" value for a key' do
        expect(service.send(:key_to_mapped_column, 'title')).to eq('xtitle')
        expect(service.send(:key_to_mapped_column, 'creator')).to eq('xcreator')
      end

      it 'returns the key itself if no mapping exists' do
        expect(service.send(:key_to_mapped_column, 'unmapped')).to eq('unmapped')
      end
    end

    describe '#format_split_text' do
      it 'handles nil split value' do
        expect(service.send(:format_split_text, nil)).to eq("Property does not split.")
      end

      it 'handles true split value using global setting' do
        result = service.send(:format_split_text, true)
        expect(result).to include("Split multiple values")
      end

      it 'handles string split patterns' do
        expect(service.send(:format_split_text, "\\|")).to include("Split multiple values with |")
        expect(service.send(:format_split_text, "[;:|]")).to include("Split multiple values with ;, :, or |")
      end
    end

    describe '#parse_split_pattern' do
      it 'parses character classes' do
        result = service.send(:parse_split_pattern, '[;:|]')
        expect(result).to eq("Split multiple values with ;, :, or |")
      end

      it 'parses escaped single characters' do
        result = service.send(:parse_split_pattern, '\\|')
        expect(result).to eq("Split multiple values with |")
      end

      it 'handles plain patterns' do
        result = service.send(:parse_split_pattern, 'abc')
        expect(result).to eq("Split multiple values with a, b, or c")
      end
    end

    describe '#remove_empty_columns' do
      let(:rows) do
        [
          ['col1', 'col2', 'col3', 'col4'],
          ['desc1', 'desc2', 'desc3', 'desc4'],
          ['data1', nil, 'data3', '---'],
          ['data1', nil, 'data3', '---']
        ]
      end

      before do
        service.instance_variable_set(:@required_headings, ['col1'])
      end

      it 'removes columns with no data' do
        result = service.send(:remove_empty_columns, rows)
        headers = result[0]

        expect(headers).to include('col1', 'col3')
        expect(headers).not_to include('col2', 'col4')
      end

      it 'keeps required headings even if empty' do
        rows[2][0] = nil
        rows[3][0] = nil
        result = service.send(:remove_empty_columns, rows)

        expect(result[0]).to include('col1')
      end
    end

    describe '#model_breakdown' do
      let(:model_name) { 'GenericWorkResource' }

      before do
        service.instance_variable_set(:@header_row, ['work_type', 'title', 'creator', 'unknown_field'])

        allow(service).to receive(:find_or_create_field_list_for).and_return(
          'GenericWorkResource' => {
            'properties' => ['title', 'creator'],
            'required_terms' => ['title']
          }
        )

        allow(service).to receive(:determine_klass_for).and_return(GenericWorkResource)
      end

      it 'marks properties as Required or Optional' do
        row = service.send(:model_breakdown, model_name)

        expect(row[0]).to eq('GenericWorkResource') # work_type
        expect(row[1]).to eq('Required')    # title (in required_terms)
        expect(row[2]).to eq('Optional')    # creator (not required)
        expect(row[3]).to eq('---')         # unknown_field
      end
    end

    describe '#uses_controlled_vocab?' do
      before do
        service.instance_variable_set(:@controlled_vocab_terms, ['rights_statement', 'license'])
      end

      it 'returns true for controlled vocab fields' do
        expect(service.send(:uses_controlled_vocab?, 'rights_statement')).to be true
      end

      it 'returns false for non-controlled vocab fields' do
        expect(service.send(:uses_controlled_vocab?, 'title')).to be false
      end
    end
  end

  describe 'integration tests' do
    context 'generating CSV for all models' do
      let(:model_name) { 'all' }

      it 'produces valid CSV output' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)

        expect(csv.length).to be >= 3  # header + description + at least one model
        expect(csv[0]).to include('work_type', 'source_identifier')
      end
    end
  end
end