# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::DeleteRecord do
  def make_context(match)
    { errors: [], source_identifier: 'source_identifier', find_existing_record: ->(_row) { match } }
  end

  def make_record(deleting: true)
    { source_identifier: 'work1', model: 'GenericWork', raw_row: {}, deleting: deleting }
  end

  it 'warns that the existing record will be deleted' do
    context = make_context(field: nil, value: 'work1')
    described_class.call(make_record, 2, context)
    expect(context[:errors].first).to include(row: 2, severity: 'warning', category: 'delete_record',
                                              column: 'source_identifier', value: 'work1')
  end

  it 'names the id column when the record was matched by id' do
    context = make_context(field: 'id', value: 'rec-1')
    described_class.call(make_record, 2, context)
    expect(context[:errors].first).to include(column: 'id', value: 'rec-1')
  end

  it 'blocks a delete row that matches no record, which the import cannot delete' do
    context = make_context(nil)
    described_class.call(make_record, 2, context)
    expect(context[:errors].first).to include(severity: 'error', category: 'delete_record_not_found', value: 'work1')
  end

  it 'leaves a record of another model, or a missing id, to the existing-record error' do
    [{ field: nil, value: 'work1', existing_model: 'Etd', model: 'GenericWork' },
     { field: 'id', value: 'rec-1', missing: true }].each do |match|
      context = make_context(match)
      described_class.call(make_record, 2, context)
      expect(context[:errors]).to be_empty
    end
  end

  it 'reports nothing when the lookup itself failed' do
    context = make_context(lookup_failed: true)
    described_class.call(make_record, 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'ignores rows that do not delete' do
    context = make_context(field: nil, value: 'work1')
    described_class.call(make_record(deleting: false), 2, context)
    expect(context[:errors]).to be_empty
  end
end
