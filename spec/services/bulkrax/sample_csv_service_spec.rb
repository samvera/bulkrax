# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService do
  let(:service) { described_class.new(model_name: model_name) }
  let(:model_name) { nil }

  # Shared test setup
  before(:each) do
    stub_models_and_dependencies
  end

  describe '.call' do
    context 'when Hyrax is not defined' do
      before { hide_const("Hyrax") }

      it 'raises NameError' do
        expect { described_class.call }.to raise_error(NameError, "Hyrax is not defined")
      end
    end

    context 'when Hyrax is defined' do
      it 'returns a file path when output is file' do
        # Mock the file operations
        allow(CSV).to receive(:open).and_return(true)
        allow(FileUtils).to receive(:mkdir_p).and_return(true)
        
        result = described_class.call(output: 'file', model_name: 'MyWork')
        # Result can be either a String or Pathname
        expect(result.to_s).to be_a(String)
        expect(result.to_s).to include('bulkrax_template')
      end

      it 'returns a CSV string when output is csv_string' do
        result = described_class.call(output: 'csv_string', model_name: 'MyWork')
        expect(result).to be_a(String)
        expect(result).to include('work_type')
      end
    end
  end

  describe '#initialize' do
    context 'with nil model_name' do
      it 'initializes with empty models' do
        expect(service.all_models).to eq([])
      end

      it 'initializes mapping manager' do
        expect(service.mappings).to be_a(Hash)
        expect(service.mappings).to have_key('title')
      end
    end

    context 'with "all" model_name' do
      let(:model_name) { 'all' }

      it 'loads all configured models' do
        expect(service.all_models).to include('MyWork', 'AnotherWork')
        expect(service.all_models).to include('Hyrax::FileSet')
      end
    end

    context 'with specific model_name' do
      let(:model_name) { 'MyWork' }

      it 'loads only the specified model' do
        expect(service.all_models).to eq(['MyWork'])
      end
    end

    context 'with invalid model_name' do
      let(:model_name) { 'NonExistentModel' }

      it 'handles invalid model gracefully' do
        expect(service.all_models).to eq([])
      end
    end
  end

  describe '#to_file' do
    let(:model_name) { 'MyWork' }

    it 'creates a CSV file at the specified path' do
      file_path = Rails.root.join('tmp', 'test.csv')

      # Mock the file operations
      csv_double = instance_double(CSV)
      allow(CSV).to receive(:open).with(file_path, "w").and_yield(csv_double)
      allow(csv_double).to receive(:<<).and_return(true)
      allow(FileUtils).to receive(:mkdir_p).and_return(true)

      result = service.to_file(file_path: file_path)

      # Result might be a Pathname, so convert to string for comparison
      expect(result.to_s).to eq(file_path.to_s)
      expect(CSV).to have_received(:open).with(file_path, "w")
    end

    it 'creates a CSV file at default path when none provided' do
      # Mock file operations
      csv_double = instance_double(CSV)
      allow(CSV).to receive(:open).with(anything, "w").and_yield(csv_double)
      allow(csv_double).to receive(:<<).and_return(true)
      allow(FileUtils).to receive(:mkdir_p).and_return(true)

      result = service.to_file

      # Result might be a Pathname, so convert to string
      expect(result.to_s).to be_a(String)
      expect(result.to_s).to include('bulkrax_template')
      expect(CSV).to have_received(:open).with(anything, "w")
    end
  end

  describe '#to_csv_string' do
    context 'with no models' do
      it 'returns CSV with headers only' do
        result = service.to_csv_string

        expect(result).to be_a(String)
        csv = CSV.parse(result)

        # Should have at least header and description rows
        expect(csv.length).to be >= 2
        expect(csv[0]).to include('work_type', 'source_identifier')
      end
    end

    context 'with a specific model' do
      let(:model_name) { 'MyWork' }

      it 'returns CSV with model data' do
        result = service.to_csv_string

        expect(result).to be_a(String)
        csv = CSV.parse(result)

        # Should have header, description, and model row
        expect(csv.length).to eq(3)
        expect(csv[0]).to include('work_type', 'source_identifier')
        expect(csv[2][0]).to eq('MyWork')
      end
    end

    context 'with all models' do
      let(:model_name) { 'all' }

      it 'returns CSV with all model data' do
        result = service.to_csv_string

        expect(result).to be_a(String)
        csv = CSV.parse(result)

        # Should have header, description, and one row per model
        expect(csv.length).to be >= 4 # header + description + 2+ models

        # Check that different models are present
        model_names = csv[2..-1].map { |row| row[0] }
        expect(model_names).to include('MyWork', 'AnotherWork')
      end
    end
  end

  describe 'integration tests' do
    describe 'CSV structure validation' do
      let(:model_name) { 'MyWork' }

      it 'includes required columns in correct order' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)
        headers = csv[0]

        # Check first few columns are in expected order
        expect(headers[0]).to eq('work_type')
        expect(headers[1]).to eq('source_identifier')

        # Check that important columns exist
        expect(headers).to include('visibility')
        expect(headers).to include('xtitle')
        expect(headers).to include('xcreator')
      end

      it 'includes descriptions for columns' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)
        descriptions = csv[1]

        # Check that descriptions are present
        expect(descriptions[0]).to include('work types configured')
        expect(descriptions[1]).to include('unique identifier')
      end

      it 'marks required fields correctly' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)
        model_row = csv[2]

        # source_identifier should always be required
        source_id_index = csv[0].index('source_identifier')
        expect(model_row[source_id_index]).to eq('Required')

        # work_type should have the model name
        expect(model_row[0]).to eq('MyWork')
      end
    end

    describe 'empty column removal' do
      let(:model_name) { 'MyWork' }

      it 'removes columns with no data' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)
        headers = csv[0]

        # All columns should have some data (header, description, or value)
        headers.each_with_index do |_header, index|
          column_values = csv.map { |row| row[index] }
          has_content = column_values.any? { |val| val && val != '' && val != '---' }
          expect(has_content).to be true
        end
      end
    end

    describe 'multiple model handling' do
      let(:model_name) { 'all' }

      it 'generates appropriate rows for each model' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)

        # Get model rows (skip header and description)
        model_rows = csv[2..-1]

        # Each model should have its name in the work_type column
        work_types = model_rows.map { |row| row[0] }
        expect(work_types).to include('MyWork')
        expect(work_types).to include('AnotherWork')

        # Each row should have consistent length
        row_lengths = model_rows.map(&:length)
        expect(row_lengths.uniq.length).to eq(1)
      end
    end
  end

  private

  def stub_models_and_dependencies
    # First, stub ValkyrieObjectFactory to prevent schema access issues
    stub_const('Bulkrax::ValkyrieObjectFactory', Class.new do
      def self.schema_properties(klass)
        # Just return the properties as-is
        klass.properties.keys.map(&:to_s)
      end
    end)

    # Create simple test models without schema complexity
    my_work_model = Class.new do
      def self.name; 'MyWork'; end
      def self.to_s; 'MyWork'; end
      def self.properties
        { 'title' => {}, 'creator' => {}, 'description' => {} }
      end
      def self.respond_to?(method, _include_all = false)
        [:properties, :name, :to_s].include?(method) || super(method)
      end
    end

    another_work_model = Class.new do
      def self.name; 'AnotherWork'; end
      def self.to_s; 'AnotherWork'; end
      def self.properties
        { 'title' => {}, 'description' => {} }
      end
      def self.respond_to?(method, _include_all = false)
        [:properties, :name, :to_s].include?(method) || super(method)
      end
    end

    collection_model = Class.new do
      def self.name; 'Collection'; end
      def self.to_s; 'Collection'; end
      def self.properties
        { 'title' => {}, 'description' => {} }
      end
      def self.respond_to?(method, _include_all = false)
        [:properties, :name, :to_s].include?(method) || super(method)
      end
    end

    fileset_model = Class.new do
      def self.name; 'Hyrax::FileSet'; end
      def self.to_s; 'Hyrax::FileSet'; end
      def self.properties
        { 'title' => {} }
      end
      def self.respond_to?(method, _include_all = false)
        [:properties, :name, :to_s].include?(method) || super(method)
      end
    end

    # Stub the model constants
    stub_const('MyWork', my_work_model)
    stub_const('AnotherWork', another_work_model)
    stub_const('Collection', collection_model)

    # Create and stub Hyrax module
    hyrax_module = Class.new do
      def self.config
        OpenStruct.new(curation_concerns: [MyWork, AnotherWork])
      end
    end
    stub_const('Hyrax', hyrax_module)

    # Stub Hyrax::FileSet after Hyrax is defined
    stub_const('Hyrax::FileSet', fileset_model)

    # Stub other dependencies
    stub_admin_set_service
    stub_user_model
    stub_bulkrax_configuration
    stub_qa_authorities
  end

  def stub_admin_set_service
    admin_set_service = Class.new do
      def self.find_or_create_default_admin_set
        OpenStruct.new(id: 'admin-set-123')
      end
    end
    stub_const('Hyrax::AdminSetCreateService', admin_set_service)
  end

  def stub_user_model
    user_class = Class.new do
      def self.find_by(args)
        OpenStruct.new(id: 1) if args[:email] == 'admin@example.com'
      end
    end
    stub_const('User', user_class)
  end

  def stub_bulkrax_configuration
    allow(Bulkrax).to receive(:default_work_type).and_return('MyWork')
    allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
    allow(Bulkrax).to receive(:file_model_class).and_return(Hyrax::FileSet)
    allow(Bulkrax).to receive(:config).and_return(OpenStruct.new(object_factory: nil))

    allow(Bulkrax).to receive(:field_mappings).and_return(
      "Bulkrax::CsvParser" => {
        "title" => { "from" => ["xtitle"], "split" => /\s*[|]\s*/ },
        "creator" => { "from" => ["xcreator"], "split" => true },
        "description" => { "from" => ["xdescription"], "split" => true },
        "file" => { "from" => ["xlocalfiles"], "split" => /\s*[|]\s*/ },
        "remote_files" => { "from" => ["xrefs"], "split" => /\s*[|]\s*/ },
        "children" => { "from" => ["xchildren"], "related_children_field_mapping" => true },
        "parents" => { "from" => ["xparents"], "related_parents_field_mapping" => true },
        "visibility" => { "from" => ["visibility"] },
        "source_identifier" => { "from" => ["source_identifier"], "source_identifier" => true },
        "work_type" => { "from" => ["work_type"] }
      }
    )

    allow(Bulkrax).to receive(:multi_value_element_split_on).and_return(/\s*[|]\s*/)
  end

  def stub_qa_authorities
    qa_registry_mock = OpenStruct.new
    qa_registry_mock.define_singleton_method(:instance_variable_get) do |var_name|
      return {} unless var_name == '@hash'
      {
        'rights_statements' => OpenStruct.new(klass: Class.new),
        'licenses' => OpenStruct.new(klass: Class.new)
      }
    end

    qa_local = Class.new do
      def self.registry
        qa_registry_mock
      end
    end
    stub_const('Qa::Authorities::Local', qa_local)
    stub_const('Qa::Authorities::Local::FileBasedAuthority', Class.new)
  end
end
