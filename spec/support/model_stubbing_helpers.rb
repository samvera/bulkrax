# frozen_string_literal: true

# Provides helper methods for stubbing Bulkrax model classes and dependencies in specs.
module ModelStubbingHelpers
  # Stubs GenericWork, Collection, and FileSet model classes with proper methods
  # and configures Hyrax/Bulkrax dependencies for testing.
  #
  # This creates fully functional test doubles that include:
  # - Model classes with `.properties`, `.name`, `.to_s`, and `.respond_to?` methods
  # - Hyrax configuration (curation concerns, collection/file models)
  # - Bulkrax field mappings (title, creator, description, model, parents, file, source_identifier)
  # - ValkyrieObjectFactory stub to prevent schema access issues
  # - ModelLoader stub to recognize the test models
  #
  # Models created:
  # - GenericWork: properties = { 'title', 'creator', 'description' }
  # - Collection: properties = { 'title' }
  # - FileSet: properties = { 'title', 'file' }
  #
  # @example Basic usage in a spec
  #   RSpec.describe Bulkrax::CsvValidationService do
  #     before(:each) do
  #       stub_bulkrax_models
  #     end
  #
  #     it 'works with GenericWork' do
  #       expect(GenericWork.properties).to include('title')
  #     end
  #   end
  #
  # @return [void]
  def stub_bulkrax_models
    # First, stub ValkyrieObjectFactory to prevent schema access issues
    stub_const('Bulkrax::ValkyrieObjectFactory', Class.new do
      def self.schema_properties(klass)
        # Just return the properties as-is
        klass.properties.keys.map(&:to_s)
      end
    end)

    # Create GenericWork model (commonly used in examples)
    generic_work_model = Class.new do
      def self.name
        'GenericWork'
      end

      def self.to_s
        'GenericWork'
      end

      def self.properties
        { 'title' => {}, 'creator' => {}, 'description' => {} }
      end

      def self.respond_to?(method, _include_all = false)
        [:properties, :name, :to_s].include?(method) || super
      end
    end

    # Create Collection model
    collection_model = Class.new do
      def self.name
        'Collection'
      end

      def self.to_s
        'Collection'
      end

      def self.properties
        { 'title' => {} }
      end

      def self.respond_to?(method, _include_all = false)
        [:properties, :name, :to_s].include?(method) || super
      end
    end

    # Create FileSet model
    fileset_model = Class.new do
      def self.name
        'FileSet'
      end

      def self.to_s
        'FileSet'
      end

      def self.properties
        { 'title' => {}, 'file' => {} }
      end

      def self.respond_to?(method, _include_all = false)
        [:properties, :name, :to_s].include?(method) || super
      end
    end

    # Stub the constants
    stub_const('GenericWork', generic_work_model)
    stub_const('Collection', collection_model)
    stub_const('FileSet', fileset_model)

    # Stub Hyrax configuration
    allow(Hyrax).to receive(:config).and_return(double(curation_concerns: [GenericWork]))
    allow(Bulkrax).to receive(:collection_model_class).and_return(Collection)
    allow(Bulkrax).to receive(:file_model_class).and_return(FileSet)

    # Stub ModelLoader to recognize these models
    allow(Bulkrax::CsvValidationService::ModelLoader).to receive(:determine_klass_for) do |name|
      case name
      when 'GenericWork' then GenericWork
      when 'Collection' then Collection
      when 'FileSet' then FileSet
      end
    end

    # Stub field mappings
    allow(Bulkrax).to receive(:field_mappings).and_return({
                                                            'Bulkrax::CsvParser' => {
                                                              'title' => { 'from' => ['title'], 'split' => false },
                                                              'creator' => { 'from' => ['creator'], 'split' => false },
                                                              'description' => { 'from' => ['description'], 'split' => false },
                                                              'model' => { 'from' => ['model'], 'split' => false },
                                                              'parents' => { 'from' => ['parents'], 'related_parents_field_mapping' => true },
                                                              'file' => { 'from' => ['file'], 'split' => false },
                                                              'source_identifier' => { 'from' => ['source_identifier'], 'source_identifier' => true }
                                                            }
                                                          })
  end
end

RSpec.configure do |config|
  config.include ModelStubbingHelpers
end
