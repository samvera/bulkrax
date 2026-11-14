# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvRow::DuplicateIdentifier do
  def make_context(find_existing: nil)
    { errors: [], warnings: [], seen_ids: {}, source_identifier: 'source_identifier',
      find_existing_record: find_existing }
  end

  def make_record(source_id)
    { source_identifier: source_id, model: 'GenericWork', parent: nil, children: nil, file: nil, raw_row: {} }
  end

  it 'adds nothing for a unique identifier that does not exist in the repo' do
    context = make_context(find_existing: ->(_row) {})
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors]).to be_empty
    expect(context[:seen_ids]).to eq('work1' => 2)
  end

  it 'adds a warning for a unique identifier that already exists in the repo' do
    context = make_context(find_existing: ->(_row) { { field: nil, value: 'work1' } })
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors].length).to eq(1)
    warning = context[:errors].first
    expect(warning[:severity]).to eq('warning')
    expect(warning[:category]).to eq('existing_source_identifier')
    expect(warning[:row]).to eq(2)
    expect(warning[:value]).to eq('work1')
    expect(warning[:column]).to eq('source_identifier')
  end

  it "warns under the id column when the row's id matches an existing record" do
    context = make_context(find_existing: ->(_row) { { field: 'id', value: 'rec-1' } })
    described_class.call(make_record('work1'), 2, context)
    warning = context[:errors].first
    expect(warning).to include(severity: 'warning', category: 'existing_source_identifier', column: 'id', value: 'rec-1')
  end

  it 'reports an error when the existing record is of another model' do
    context = make_context(find_existing: ->(_row) { { field: nil, value: 'work1', existing_model: 'Etd', model: 'GenericWork' } })
    described_class.call(make_record('work1'), 2, context)
    error = context[:errors].first
    expect(error).to include(severity: 'error', category: 'existing_record_model_mismatch', column: 'source_identifier', value: 'work1')
    expect(error[:message]).to include('Etd', 'GenericWork')
  end

  it 'suggests clearing the id when the record of another model was matched by id' do
    context = make_context(find_existing: ->(_row) { { field: 'id', value: 'rec-1', existing_model: 'Etd', model: 'GenericWork' } })
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors].first[:suggestion]).to include('Etd', 'leave the id value blank')
  end

  it 'warns that a remove-and-rerun row deletes the record and imports it again' do
    context = make_context(find_existing: ->(_row) { { field: nil, value: 'work1' } })
    described_class.call(make_record('work1').merge(rerunning: true), 2, context)
    expect(context[:errors].first).to include(severity: 'warning', category: 'remove_and_rerun_record', value: 'work1')
    expect(context[:errors].first[:message]).to include('delete it and import it again')
  end

  it 'treats a row that both deletes and reruns as a delete, as import does' do
    context = make_context(find_existing: ->(_row) { { field: nil, value: 'work1' } })
    described_class.call(make_record('work1').merge(deleting: true, rerunning: true), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'reports nothing when the lookup itself failed' do
    context = make_context(find_existing: ->(_row) { { lookup_failed: true } })
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'gives a delete row no update warning' do
    context = make_context(find_existing: ->(_row) { { field: nil, value: 'work1' } })
    described_class.call(make_record('work1').merge(deleting: true), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'still reports a delete row whose record is of another model' do
    context = make_context(find_existing: ->(_row) { { field: nil, value: 'work1', existing_model: 'Etd', model: 'GenericWork' } })
    described_class.call(make_record('work1').merge(deleting: true), 2, context)
    expect(context[:errors].first).to include(category: 'existing_record_model_mismatch')
  end

  it 'reports an error when the id names no existing record' do
    context = make_context(find_existing: ->(_row) { { field: 'id', value: 'rec-1', missing: true } })
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors].first).to include(severity: 'error', category: 'existing_record_id_not_found', column: 'id', value: 'rec-1')
  end

  it 'adds no warning when no lookup is provided' do
    context = make_context
    described_class.call(make_record('work1'), 2, context)
    expect(context[:errors]).to be_empty
  end

  it 'records an error for a duplicate identifier' do
    context = make_context
    described_class.call(make_record('work1'), 2, context)
    described_class.call(make_record('work1'), 3, context)

    expect(context[:errors].length).to eq(1)
    error = context[:errors].first
    expect(error[:category]).to eq('duplicate_source_identifier')
    expect(error[:row]).to eq(3)
    expect(error[:value]).to eq('work1')
  end

  context 'when fill_in_blank_source_identifiers is configured' do
    before do
      allow(Bulkrax).to receive(:fill_in_blank_source_identifiers)
        .and_return(->(_parser, _index) { SecureRandom.uuid })
    end

    it 'skips the duplicate check for blank source_identifiers' do
      context = make_context
      described_class.call(make_record(nil), 2, context)
      described_class.call(make_record(nil), 3, context)

      expect(context[:errors]).to be_empty
    end

    it 'still reports a blank-identifier row whose id names no record' do
      context = make_context(find_existing: ->(_row) { { field: 'id', value: 'rec-1', missing: true } })
      described_class.call(make_record(nil), 2, context)

      expect(context[:errors].first).to include(category: 'existing_record_id_not_found', value: 'rec-1')
    end

    it 'still records an error for duplicate non-blank identifiers' do
      context = make_context
      described_class.call(make_record('work1'), 2, context)
      described_class.call(make_record('work1'), 3, context)

      expect(context[:errors].length).to eq(1)
    end
  end
end
