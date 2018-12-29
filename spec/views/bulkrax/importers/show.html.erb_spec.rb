require 'rails_helper'

RSpec.describe "importers/show", type: :view do
  before(:each) do
    @importer = assign(:importer, Importer.create!(
      :name => "Name",
      :admin_set_id => "Admin Set",
      :user => nil,
      :frequency => "Frequency",
      :parser_klass => "Parser Klass",
      :limit => 2,
      :parser_fields => "",
      :field_mapping => ""
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Name/)
    expect(rendered).to match(/Admin Set/)
    expect(rendered).to match(//)
    expect(rendered).to match(/Frequency/)
    expect(rendered).to match(/Parser Klass/)
    expect(rendered).to match(/2/)
    expect(rendered).to match(//)
    expect(rendered).to match(//)
  end
end
