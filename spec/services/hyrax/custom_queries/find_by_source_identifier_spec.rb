require 'spec_helper'

RSpec.describe Hyrax::CustomQueries::FindBySourceIdentifier do
  describe '.queries' do
    subject { described_class.queries }
    let(:query_name) { :find_by_source_identifier }

    it { is_expected.to include(query_name) }

    it 'is registered with the Hyrax.query_service' do
      expect(Hyrax.query_service.custom_queries).to respond_to(query_name)
    end

    context ':find_by_source_identifier query' do
      it 'is valid SQL' do
        expect do
          Hyrax.query_service.custom_queries.find_by_source_identifier(work_identifier: 'source', source_identifier_value: "testing-bulkrax-1-2-3")
        end.not_to raise_error
      end
    end
  end
end