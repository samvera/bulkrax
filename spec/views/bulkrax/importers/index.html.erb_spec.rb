require 'rails_helper'

RSpec.describe "importers/index", type: :view do
  before(:each) do
    assign(:importers, [
      Importer.create!(
        :name => "Name",
        :admin_set_id => "Admin Set",
        :user => nil,
        :frequency => "Frequency",
        :parser_klass => "Parser Klass",
        :limit => 2,
        :parser_fields => "",
        :field_mapping => ""
      ),
      Importer.create!(
        :name => "Name",
        :admin_set_id => "Admin Set",
        :user => nil,
        :frequency => "Frequency",
        :parser_klass => "Parser Klass",
        :limit => 2,
        :parser_fields => "",
        :field_mapping => ""
      )
    ])
  end

  it "renders a list of importers" do
    render
    assert_select "tr>td", :text => "Name".to_s, :count => 2
    assert_select "tr>td", :text => "Admin Set".to_s, :count => 2
    assert_select "tr>td", :text => nil.to_s, :count => 2
    assert_select "tr>td", :text => "Frequency".to_s, :count => 2
    assert_select "tr>td", :text => "Parser Klass".to_s, :count => 2
    assert_select "tr>td", :text => 2.to_s, :count => 2
    assert_select "tr>td", :text => "".to_s, :count => 2
    assert_select "tr>td", :text => "".to_s, :count => 2
  end
end
