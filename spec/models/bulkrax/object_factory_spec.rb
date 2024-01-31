# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  # NOTE: Unable to put this file in spec/factories/bulkrax (where it would mirror the path in app/) because
  # (presumably) FactoryBot autoloads all files in spec/factories, which would always run this spec.
  # Why aren't there more tests?  In part because so much of the ObjectFactory require that we boot
  # up Fedora and SOLR; something that remains non-desirous due to speed.

  RSpec.describe ObjectFactory do
    subject(:object_factory) { build(:object_factory) }

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end

    describe "#transform_attributes" do
      context 'default behavior' do
        it "does not empty arrays that only have empty values" do
          attributes = { empty_array: ["", ""], empty_string: "", filled_array: ["A", "B"], filled_string: "A" }
          factory = described_class.new(attributes: attributes,
                                        source_identifier_value: 123,
                                        work_identifier: "filled_string",
                                        work_identifier_search_field: 'filled_string_sim')
          factory.base_permitted_attributes = %i[empty_array empty_string filled_array filled_string]
          expect(factory.send(:transform_attributes)).to eq(attributes.stringify_keys)
        end
      end

      context 'when :transformation_removes_blank_hash_values = true' do
        it "empties arrays that only have empty values" do
          attributes = { empty_array: ["", ""], empty_string: "", filled_array: ["A", "B"], filled_string: "A" }
          factory = described_class.new(attributes: attributes,
                                        source_identifier_value: 123,
                                        work_identifier: "filled_string",
                                        work_identifier_search_field: 'filled_string_sim')
          factory.base_permitted_attributes = %i[empty_array empty_string filled_array filled_string]
          factory.transformation_removes_blank_hash_values = true
          expect(factory.send(:transform_attributes))
            .to eq({ empty_array: [], empty_string: nil, filled_array: ["A", "B"], filled_string: "A" }.stringify_keys)
        end
      end
    end
  end
end
