# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::ObjectFactory do
  # Why aren't there more tests?  In part because so much of the ObjectFactory require that we boot
  # up Fedora and SOLR; something that remains non-desirous due to speed.
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
                                      work_identifier_search_string: 'filled_string_sim')
        factory.base_permitted_attributes = %i[empty_array empty_string filled_array filled_string]
        factory.transformation_removes_blank_hash_values = true
        expect(factory.send(:transform_attributes))
          .to eq({ empty_array: [], empty_string: nil, filled_array: ["A", "B"], filled_string: "A" }.stringify_keys)
      end
    end
  end
end
