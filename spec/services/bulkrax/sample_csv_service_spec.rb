# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SampleCsvService do
  # Define only the fake model classes we actually need for testing
  let(:fake_model_with_schema) do
    Class.new do
      def self.name
        'GenericWork'
      end

      def self.to_s
        'GenericWork'
      end

      def self.properties
        { 'title' => {}, 'creator' => {}, 'description' => {}, 'rights_statement' => {} }
      end

      def self.schema
        # Mock schema for Valkyrie models - create proper mock objects
        title_field = OpenStruct.new(name: :title, meta: { 'form' => { 'required' => true } })
        def title_field.respond_to?(method, include_all = false)
          [:meta, :name].include?(method) || super
        end

        creator_field = OpenStruct.new(name: :creator, meta: { 'form' => { 'required' => false } })
        def creator_field.respond_to?(method, include_all = false)
          [:meta, :name].include?(method) || super
        end

        [title_field, creator_field]
      end

      def self.new
        instance = allocate
        # Make singleton_class.schema return nil so it falls back to class.schema
        def instance.singleton_class
          klass = Class.new
          def klass.schema
            nil
          end
          klass
        end
        instance
      end

      # Also allow the class to respond to :schema
      def self.respond_to?(method, include_all = false)
        [:schema, :new].include?(method) || super
      end
    end
  end

  let(:fake_model_without_schema) do
    Class.new do
      def self.name
        'CollectionResource'
      end

      def self.to_s
        'CollectionResource'
      end

      def self.properties
        { 'title' => {}, 'description' => {} }
      end
    end
  end

  let(:service) { described_class.new(model_name: model_name) }
  let(:model_name) { nil }

  # Stub ALL constants before any tests run
  before(:each) do
    # Helper to create schema fields with proper respond_to?
    def create_schema_field(name_val, required)
      field = OpenStruct.new(name: name_val, meta: { 'form' => { 'required' => required } })
      field.define_singleton_method(:respond_to?) do |method, include_all = false|
        [:meta, :name].include?(method) || super(method, include_all)
      end
      field
    end

    # Create the base schema for models that have schemas
    test_schema = [
      create_schema_field(:title, true),
      create_schema_field(:creator, false)
    ]

    # Create variations of the model with different names for proper testing
    generic_work_model = Class.new do
      schema = test_schema # Capture schema in closure

      def self.name
        'GenericWork'
      end

      def self.to_s
        'GenericWork'
      end

      def self.properties
        { 'title' => {}, 'creator' => {}, 'description' => {}, 'rights_statement' => {} }
      end

      # Define schema as a class method
      define_singleton_method(:schema) { schema }

      # Define new to return an instance
      define_singleton_method(:new) do
        instance = allocate
        # Make the instance's singleton_class have a schema method that returns the same schema
        instance.define_singleton_method(:singleton_class) do
          sc = Class.new
          sc.define_singleton_method(:schema) { schema }
          sc
        end
        instance
      end

      def self.respond_to?(method, include_all = false)
        [:schema, :new, :properties].include?(method) || super
      end
    end

    image_resource_model = Class.new(fake_model_with_schema) do
      def self.name
        'ImageResource'
      end

      def self.to_s
        'ImageResource'
      end
    end

    etd_model = Class.new(fake_model_with_schema) do
      def self.name
        'Etd'
      end

      def self.to_s
        'Etd'
      end
    end

    oer_model = Class.new(fake_model_with_schema) do
      def self.name
        'Oer'
      end

      def self.to_s
        'Oer'
      end
    end

    collection_model = Class.new(fake_model_without_schema) do
      def self.name
        'CollectionResource'
      end

      def self.to_s
        'CollectionResource'
      end
    end

    fileset_model = Class.new(fake_model_without_schema) do
      def self.name
        'Hyrax::FileSet'
      end

      def self.to_s
        'Hyrax::FileSet'
      end
    end

    # Stub the models with unique names
    stub_const('GenericWorkResource', generic_work_model)
    stub_const('GenericWork', generic_work_model)
    stub_const('ImageResource', image_resource_model)
    stub_const('Etd', etd_model)
    stub_const('Oer', oer_model)
    stub_const('CollectionResource', collection_model)

    # Create Hyrax module with config method
    hyrax_module = Class.new do
      def self.config
        OpenStruct.new(
          curation_concerns: [GenericWork, ImageResource, Etd, Oer]
        )
      end
    end
    stub_const('Hyrax', hyrax_module)

    # Now we can stub Hyrax::FileSet since Hyrax exists
    stub_const('Hyrax::FileSet', fileset_model)

    # Mock Hyrax admin set service
    admin_set_service = Class.new do
      def self.find_or_create_default_admin_set
        OpenStruct.new(id: 'admin-set-123')
      end
    end
    stub_const('Hyrax::AdminSetCreateService', admin_set_service)

    # Mock User model
    user_class = Class.new do
      def self.find_by(args)
        OpenStruct.new(id: 1) if args[:email] == 'admin@example.com'
      end
    end
    stub_const('User', user_class)

    # Mock Bulkrax configuration
    allow(Bulkrax).to receive(:default_work_type).and_return('GenericWorkResource')
    allow(Bulkrax).to receive(:collection_model_class).and_return(CollectionResource)
    allow(Bulkrax).to receive(:file_model_class).and_return(Hyrax::FileSet)
    allow(Bulkrax).to receive(:config).and_return(OpenStruct.new(object_factory: nil))

    # Mock field mappings
    allow(Bulkrax).to receive(:field_mappings).and_return(
      "Bulkrax::CsvParser" => {
        "title" => { "from" => ["xtitle"], "split" => /\s*[|]\s*/ },
        "creator" => { "from" => ["xcreator"], "split" => true },
        "description" => { "from" => ["xdescription"], "split" => true },
        "rights_statement" => { "from" => ["xrights", "xrights_statement"], "split" => "\\|", "generated" => true },
        "file" => { "from" => ["xlocalfiles"], "split" => /\s*[|]\s*/ },
        "remote_files" => { "from" => ["xrefs"], "split" => /\s*[|]\s*/ },
        "children" => { "from" => ["xchildren"], "related_children_field_mapping" => true },
        "parents" => { "from" => ["xparents"], "related_parents_field_mapping" => true },
        "visibility" => { "from" => ["visibility"] },
        "source_identifier" => { "from" => ["source_identifier"], "source_identifier" => true },
        "work_type" => { "from" => ["work_type"] },
        "extent" => { "from" => ["xextent"], "split" => true },
        "department" => { "from" => ["xdepartment"] },
        "course" => { "from" => ["xcourse"] },
        "file_ids" => { "from" => ["file_ids"] }
      }
    )

    # Mock multi-value split pattern
    allow(Bulkrax).to receive(:multi_value_element_split_on).and_return(/\s*[|]\s*/)

    # Mock Bulkrax Importer
    importer_class = Class.new do
      def self.create(attrs = {})
        OpenStruct.new(attrs.merge(id: 1))
      end
    end
    stub_const('Bulkrax::Importer', importer_class)

    # Mock Qa registry for controlled vocabularies
    qa_registry_mock = OpenStruct.new
    qa_registry_mock.define_singleton_method(:instance_variable_get) do |var_name|
      return unless var_name == '@hash'
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
        expect(models).to include('GenericWork', 'ImageResource', 'Etd', 'Oer')
        expect(models).to include('CollectionResource', 'Hyrax::FileSet')
      end
    end

    context 'with specific model_name' do
      let(:model_name) { 'GenericWork' }

      it 'sets @all_models to contain only that model' do
        expect(service.instance_variable_get(:@all_models)).to eq(['GenericWork'])
      end
    end

    context 'with invalid model_name' do
      let(:model_name) { 'NonExistentModel' }

      it 'sets @all_models to empty array when constantize fails' do
        expect(service.instance_variable_get(:@all_models)).to eq([])
      end
    end

    it 'filters out generated fields from mappings' do
      mappings = service.instance_variable_get(:@mappings)
      # The service filters out generated fields
      # rights_statement is marked as generated: true, so it should be filtered
      expect(mappings).not_to have_key('rights_statement')
      # But keeps non-generated fields
      expect(mappings).to have_key('title')
      expect(mappings).to have_key('creator')
    end
  end

  describe '#to_file' do
    let(:model_name) { 'GenericWork' }
    let(:file_path) { Rails.root.join('tmp', 'test.csv') }
    let(:csv_rows) do
      [
        ['work_type', 'source_identifier', 'xtitle'],
        ['Description 1', 'Description 2', 'Description 3'],
        ['GenericWork', 'Required', 'Required']
      ]
    end

    before do
      allow(service).to receive(:csv_rows).and_return(csv_rows)
    end

    it 'creates a CSV file at the specified path' do
      csv_mock = OpenStruct.new
      csv_mock.define_singleton_method(:<<) { |_row| true }

      expect(CSV).to receive(:open).with(file_path, "w").and_yield(csv_mock)

      service.to_file(file_path: file_path)
    end

    it 'uses default path when none provided' do
      csv_mock = OpenStruct.new
      csv_mock.define_singleton_method(:<<) { |_row| true }

      expect(CSV).to receive(:open).with(anything, "w").and_yield(csv_mock)

      service.to_file
    end
  end

  describe '#to_csv_string' do
    let(:csv_rows) do
      [
        ['work_type', 'source_identifier'],
        ['Type description', 'ID description'],
        ['GenericWork', 'Required']
      ]
    end

    before do
      allow(service).to receive(:csv_rows).and_return(csv_rows)
    end

    it 'returns a CSV string' do
      result = service.to_csv_string
      expect(result).to be_a(String)
      expect(result).to include('work_type,source_identifier')
      expect(result).to include('GenericWork,Required')
    end
  end

  describe '#to_importer' do
    before do
      allow(service).to receive(:to_file)
    end

    it 'creates a Bulkrax::Importer with correct parameters' do
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
      let(:model_name) { 'GenericWork' }

      before do
        allow(service).to receive(:fill_header_row).and_return(['work_type', 'xtitle'])
        allow(service).to receive(:property_explanations).and_return([
                                                                       { 'work_type' => 'Type description' },
                                                                       { 'xtitle' => 'Title description' }
                                                                     ])
        allow(service).to receive(:model_breakdown).and_return(['GenericWork', 'Required'])
        allow(service).to receive(:remove_empty_columns) { |rows| rows }
      end

      it 'generates header, explanation, and model rows' do
        rows = service.send(:csv_rows)
        expect(rows.length).to eq(3) # Changed from have_exactly(3).items
        expect(rows[0]).to eq(['work_type', 'xtitle'])
        expect(rows[1]).to include('Type description', 'Title description')
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
      end
    end

    describe '#determine_klass_for' do
      context 'with standard object factory' do
        it 'returns the constantized class' do
          result = service.send(:determine_klass_for, 'GenericWork')
          expect(result).to eq(GenericWork)
        end

        it 'returns nil for invalid class names' do
          result = service.send(:determine_klass_for, 'InvalidClass')
          expect(result).to be_nil
        end
      end

      context 'with Valkyrie object factory' do
        before do
          stub_const('Bulkrax::ValkyrieObjectFactory', Class.new)
          allow(Bulkrax.config).to receive(:object_factory).and_return(Bulkrax::ValkyrieObjectFactory)

          # Create a resolver that returns the class when called
          resolver = OpenStruct.new
          resolver.define_singleton_method(:call) do |model_name|
            GenericWork if model_name == 'GenericWork'
          end

          valkyrie_module = Class.new do
            def self.config
              resolver = OpenStruct.new
              resolver.define_singleton_method(:call) do |model_name|
                GenericWork if model_name == 'GenericWork'
              end
              OpenStruct.new(resource_class_resolver: resolver)
            end
          end
          stub_const('Valkyrie', valkyrie_module)
        end

        it 'uses Valkyrie resource class resolver' do
          result = service.send(:determine_klass_for, 'GenericWork')
          expect(result).to eq(GenericWork)
        end
      end
    end

    describe '#find_or_create_field_list_for' do
      let(:model_name) { 'GenericWork' }

      it 'creates and caches field list for a model' do
        result = service.send(:find_or_create_field_list_for, model_name: model_name)

        expect(result).to have_key('GenericWork')
        expect(result['GenericWork']).to have_key('properties')
        expect(result['GenericWork']['properties']).to include('title', 'creator')
      end

      it 'returns cached result on second call' do
        first_call = service.send(:find_or_create_field_list_for, model_name: model_name)
        second_call = service.send(:find_or_create_field_list_for, model_name: model_name)

        expect(first_call).to eq(second_call)
      end

      it 'returns empty hash for nil class' do
        allow(service).to receive(:determine_klass_for).and_return(nil)
        result = service.send(:find_or_create_field_list_for, model_name: 'InvalidModel')

        expect(result).to eq({})
      end
    end

    describe '#load_required_terms_for' do
      context 'with schema-based model' do
        let(:schema_model) do
          Class.new do
            def self.name
              'TestModel'
            end

            def self.schema
              title_field = OpenStruct.new(name: :title, meta: { 'form' => { 'required' => true } })
              title_field.define_singleton_method(:respond_to?) do |method, include_all = false|
                [:meta, :name].include?(method) || super(method, include_all)
              end

              creator_field = OpenStruct.new(name: :creator, meta: { 'form' => { 'required' => false } })
              creator_field.define_singleton_method(:respond_to?) do |method, include_all = false|
                [:meta, :name].include?(method) || super(method, include_all)
              end

              [title_field, creator_field]
            end

            def self.new
              obj = allocate
              # Make singleton_class.schema return the class schema
              obj.define_singleton_method(:singleton_class) do
                self.class
              end
              obj
            end

            def self.respond_to?(method, include_all = false)
              [:schema, :new].include?(method) || super
            end
          end
        end

        it 'returns required fields from schema' do
          result = service.send(:load_required_terms_for, klass: schema_model)
          expect(result).to include('title')
          expect(result).not_to include('creator')
        end
      end

      context 'with non-schema model' do
        it 'returns empty array' do
          result = service.send(:load_required_terms_for, klass: CollectionResource)
          expect(result).to eq([])
        end
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
  end

  describe 'integration tests' do
    context 'generating CSV for all models' do
      let(:model_name) { 'all' }

      it 'produces valid CSV output' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)

        expect(csv.length).to be >= 3 # header + description + at least one model
        expect(csv[0]).to include('work_type', 'source_identifier')
      end
    end

    context 'generating CSV for specific model' do
      let(:model_name) { 'GenericWork' }

      it 'includes only properties for that model' do
        csv_string = service.to_csv_string
        csv = CSV.parse(csv_string)

        # Should have exactly 3 rows: header, descriptions, and one model row
        expect(csv.length).to eq(3)
        expect(csv[2][0]).to eq('GenericWork') # work_type column
      end
    end
  end
end
