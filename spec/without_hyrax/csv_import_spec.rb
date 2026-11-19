# frozen_string_literal: true

return unless ENV['BULKRAX_WITH_HYRAX'] == 'false'

require_relative 'support/app_without_hyrax'

RSpec.describe 'Importing a CSV without Hyrax' do
  include_context 'a Bulkrax app without Hyrax'

  it 'creates a work for each row' do
    importer = import(<<~CSV)
      bulkrax_identifier,title,creator
      work-1,First work,Ada;Grace
      work-2,Second work,Alan
    CSV

    expect(Work.order(:bulkrax_identifier).pluck(:bulkrax_identifier, :title, :creator))
      .to eq([['work-1', 'First work', ['Ada', 'Grace']], ['work-2', 'Second work', ['Alan']]])
    expect(importer.entries.map(&:status)).to all(eq('Complete'))
    expect(importer.last_run.processed_records).to eq(2)
    expect(importer.status).to eq('Complete')
  end

  it 'splits values on the pattern an app configures' do
    Bulkrax.config.multi_value_element_split_on = /\s*;\s*/
    import("bulkrax_identifier,title,creator\nwork-1,First work,Lovelace: Ada;Hopper: Grace\n")

    expect(Work.pluck(:creator)).to eq([['Lovelace: Ada', 'Hopper: Grace']])
  ensure
    Bulkrax.config.multi_value_element_split_on = nil
  end

  it 'updates the existing work when a row is imported again' do
    import("bulkrax_identifier,title\nwork-1,First title\n")
    import("bulkrax_identifier,title\nwork-1,Second title\n")

    expect(Work.pluck(:bulkrax_identifier, :title)).to eq([['work-1', 'Second title']])
  end

  it 'adds child works to the parent work they name' do
    importer = import(<<~CSV)
      bulkrax_identifier,title,parents
      parent,Parent work,
      child-1,First child,parent
      child-2,Second child,parent
    CSV

    parent = Work.find_by(bulkrax_identifier: 'parent')
    expect(parent.ordered_members.to_a.map(&:bulkrax_identifier)).to contain_exactly('child-1', 'child-2')
    expect(importer.last_run.processed_relationships).to eq(2)
    expect(Bulkrax::PendingRelationship.count).to eq(0)
  end

  it 'keeps a parent work its children when the same rows are imported again' do
    csv = <<~CSV
      bulkrax_identifier,title,parents
      parent,Parent work,
      child-1,First child,parent
    CSV
    import(csv)
    importer = import(csv)

    parent = Work.find_by(bulkrax_identifier: 'parent')
    expect(parent.ordered_members.to_a.map(&:bulkrax_identifier)).to eq(['child-1'])
    expect(importer.last_run.processed_relationships).to eq(1)
    expect(Bulkrax::PendingRelationship.count).to eq(0)
  end

  it 'fails the relationship to a parent that does not exist' do
    importer = import(<<~CSV)
      bulkrax_identifier,title,parents
      child-1,First child,missing
    CSV

    expect(importer.last_run.failed_relationships).to eq(1)
    expect(Bulkrax::PendingRelationship.pluck(:status_message))
      .to eq(['Parent record missing not yet available for creating relationships with children records.'])
  end
end
