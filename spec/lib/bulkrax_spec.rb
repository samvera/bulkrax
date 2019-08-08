require 'rails_helper'

RSpec.describe Bulkrax do
  describe '#mattr_accessor' do
    context 'parsers' do
      it 'has a default' do
        expect(described_class.parsers).to eq([
                                                { class_name: 'Bulkrax::OaiDcParser', name: 'OAI - Dublin Core', partial: 'oai_fields' },
                                                { class_name: 'Bulkrax::OaiQualifiedDcParser', name: 'OAI - Qualified Dublin Core', partial: 'oai_fields' },
                                                { class_name: 'Bulkrax::CsvParser', name: 'CSV - Comma Separated Values', partial: 'csv_fields' }
                                              ])
      end

      it 'is settable' do
        expect(described_class).to respond_to(:parsers=)
      end
    end

    context 'reserved_properties' do
      it 'has a default' do
        expect(described_class.reserved_properties).to eq(%w[
                                                            create_date
                                                            modified_date
                                                            date_modified
                                                            date_uploaded
                                                            depositor
                                                            arkivo_checksum
                                                            has_model
                                                            head
                                                            label
                                                            import_url
                                                            on_behalf_of
                                                            proxy_depositor
                                                            owner
                                                            state
                                                            tail
                                                            original_url
                                                            relative_path
                                                          ])
      end

      it 'is settable' do
        expect(described_class).to respond_to(:reserved_properties=)
      end
    end

    context 'default_field_mapping' do
      it 'has a default' do
        expect(described_class.default_field_mapping).to be_a(Proc)
      end

      it 'is responds with default hash' do
        expect(described_class.default_field_mapping.call('creator')).to eq({"creator"=>{:excluded=>false, :from=>["creator"], :if=>nil, :parsed=>false, :split=>false}})
      end
    end

    context 'field_mappings' do
      it 'has defaults for oaidc and qdc' do
        expect(described_class.field_mappings.keys).to eq(["Bulkrax::OaiDcParser", "Bulkrax::OaiQualifiedDcParser"])
      end
    end
  end
end
