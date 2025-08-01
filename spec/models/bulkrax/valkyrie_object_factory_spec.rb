# frozen_string_literal: false

require 'rails_helper'

module Bulkrax
  # NOTE: Unable to put this file in spec/factories/bulkrax (where it would mirror the path in app/) because
  # (presumably) FactoryBot autoloads all files in spec/factories, which would always run this spec.
  # Why aren't there more tests?  In part because so much of the ObjectFactory require that we boot
  # up Fedora and SOLR; something that remains non-desirous due to speed.

  RSpec.describe ValkyrieObjectFactory do
    describe '.search_by_property' do
      let(:active_fedora_relation) { instance_double('ActiveFedora::Relation') }
      let(:generic_works) do
        [
          FactoryBot.build(:work, title: ["Specific Title"]),
          FactoryBot.build(:another_work, title: ["Title"])
        ]
      end
      let(:klass) { double(where: generic_works) }
      before do
        Hyrax.query_service.custom_queries.register_query_handler(Wings::CustomQueries::FindBySourceIdentifier)
        stub_request(:get, "http://localhost:8985/solr/hydra-test/select?fl=id&q=_query_:%22%7B!field%20f=bulkrax_identifier_tesim%7DTitle%22&qt=standard&rows=1000&sort=system_create_dtsi%20asc&start=0&wt=json")
          .with(
            headers: {
              'Accept' => '*/*',
              'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
              'User-Agent' => 'Faraday v2.13.4'
            }
          )
          .to_return(status: 200, body: '{}', headers: {})
        allow(ActiveFedora::Base).to receive(:where).with({ "bulkrax_identifier_tesim" => "Title" }).and_return(active_fedora_relation)
        allow(active_fedora_relation).to receive(:detect).and_yield(generic_works[1])
      end
      it 'does find the collection with a partial match' do
        work = described_class.search_by_property(
          value: "Title",
          search_field: "bulkrax_identifier_tesim",
          name_field: :bulkrax_identifier,
          klass: klass
        )
        expect(work.title).to eq(["Title"])
      end
    end
  end
end
