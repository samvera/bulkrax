require 'rails_helper'

RSpec.describe "importers/edit", type: :view do
  before(:each) do
    @importer = assign(:importer, Importer.create!(
      :name => "MyString",
      :admin_set_id => "MyString",
      :user => nil,
      :frequency => "MyString",
      :parser_klass => "MyString",
      :limit => 1,
      :parser_fields => "",
      :field_mapping => ""
    ))
  end

  it "renders the edit importer form" do
    render

    assert_select "form[action=?][method=?]", importer_path(@importer), "post" do

      assert_select "input[name=?]", "importer[name]"

      assert_select "input[name=?]", "importer[admin_set_id]"

      assert_select "input[name=?]", "importer[user_id]"

      assert_select "input[name=?]", "importer[frequency]"

      assert_select "input[name=?]", "importer[parser_klass]"

      assert_select "input[name=?]", "importer[limit]"

      assert_select "input[name=?]", "importer[parser_fields]"

      assert_select "input[name=?]", "importer[field_mapping]"
    end
  end
end
