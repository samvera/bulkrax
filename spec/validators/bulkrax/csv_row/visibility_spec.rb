# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::Visibility do
  subject(:call) { described_class.call(record, 2, context) }

  let(:errors) { [] }
  let(:mappings) { {} }
  let(:context) { { errors: errors, mappings: mappings } }
  let(:model) { 'GenericWork' }
  let(:record) { { source_identifier: 'work-1', model: model, raw_row: raw_row } }

  before { allow(Bulkrax).to receive(:object_factory).and_return(Bulkrax::ValkyrieObjectFactory) }

  context 'when the row names an embargo that has already ended' do
    let(:raw_row) do
      { 'visibility' => 'embargo', 'embargo_release_date' => '2020-01-01', 'visibility_during_embargo' => 'restricted' }
    end

    it 'reports the release date' do
      call

      expect(errors).to contain_exactly(
        hash_including(row: 2, source_identifier: 'work-1', severity: 'error', category: 'past_embargo_date',
                       column: 'embargo_release_date', value: '2020-01-01',
                       message: 'The embargo release date 2020-01-01 is not after today.')
      )
    end
  end

  context "when the row's visibility is not one Hyrax knows" do
    let(:raw_row) { { 'visibility' => 'bogus' } }

    it 'reports the visibility' do
      call

      expect(errors).to contain_exactly(hash_including(category: 'unknown_visibility', column: 'visibility', value: 'bogus'))
    end
  end

  context 'when the row has two visibility columns' do
    let(:raw_row) { { 'visibility' => 'open', 'visibility_2' => 'bogus' } }

    it 'checks the last one, which import keeps' do
      call

      expect(errors).to contain_exactly(hash_including(category: 'unknown_visibility', value: 'bogus'))
    end
  end

  context 'when the visibility mapping is excluded' do
    let(:mappings) { { 'visibility' => { 'from' => ['visibility'], 'excluded' => true } } }
    let(:raw_row) { { 'visibility' => 'bogus' } }

    it 'reports nothing, as import ignores the column' do
      call

      expect(errors).to be_empty
    end
  end

  context 'when the mapping reads the visibility column into another field' do
    let(:mappings) { { 'access_right' => { 'from' => ['visibility'] } } }
    let(:raw_row) { { 'visibility' => 'Public' } }

    it 'reports nothing, as import does not read it as the visibility' do
      call

      expect(errors).to be_empty
    end
  end

  context "when the visibility mapping's condition rejects the cell" do
    let(:mappings) { { 'visibility' => { 'from' => ['visibility'], 'if' => ['match?', '^open$'] } } }
    let(:raw_row) { { 'visibility' => 'bogus' } }

    it "reports nothing, as import drops the cell and uses the importer's visibility" do
      call

      expect(errors).to be_empty
    end
  end

  context 'when the visibility mapping fills a nested object' do
    let(:mappings) { { 'visibility' => { 'from' => ['access'], 'object' => 'single_object' } } }
    let(:raw_row) { { 'access' => 'Public' } }

    it 'reports nothing, as import does not read it as the visibility' do
      call

      expect(errors).to be_empty
    end
  end

  context 'when the row names an embargo with no date' do
    let(:raw_row) { { 'visibility' => 'embargo', 'visibility_during_embargo' => 'restricted' } }

    it 'reports nothing, as import accepts it' do
      call

      expect(errors).to be_empty
    end
  end

  context 'when the row is a collection' do
    let(:model) { 'Collection' }
    let(:raw_row) { { 'visibility' => 'embargo', 'embargo_release_date' => '2020-01-01' } }

    it "reports an embargo, which a collection's form does not take" do
      call

      expect(errors).to contain_exactly(
        hash_including(category: 'unknown_collection_visibility', column: 'visibility', value: 'embargo',
                       message: 'The visibility "embargo" is not open, authenticated or restricted, the only visibilities a collection takes.')
      )
    end
  end

  context 'when the row names the collection model in lower case with underscores' do
    let(:model) { 'hyrax/pcdm_collection' }
    let(:raw_row) { { 'visibility' => 'embargo', 'embargo_release_date' => '2020-01-01' } }

    around do |example|
      configured = Bulkrax.collection_model_class
      Bulkrax.collection_model_class = Hyrax::PcdmCollection
      example.run
    ensure
      Bulkrax.collection_model_class = configured
    end

    it 'checks it as a collection, as import does' do
      call

      expect(errors).to contain_exactly(hash_including(category: 'unknown_collection_visibility'))
    end
  end

  context 'when the row deletes its record' do
    let(:record) { { source_identifier: 'work-1', model: model, deleting: true, raw_row: { 'visibility' => 'bogus' } } }

    it 'reports nothing' do
      call

      expect(errors).to be_empty
    end
  end
end
