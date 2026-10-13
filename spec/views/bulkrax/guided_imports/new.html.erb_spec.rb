# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'bulkrax/guided_imports/new', type: :view do
  let(:user) { FactoryBot.create(:user) }
  let(:page) { Nokogiri::HTML(rendered) }

  before do
    view.extend Bulkrax::Engine.routes.url_helpers
    view.extend Bulkrax::ImportersHelper
    ability = Ability.new(user)
    view.define_singleton_method(:current_user) { user }
    view.define_singleton_method(:current_ability) { ability }
    allow(Bulkrax.config).to receive(:guided_import_metrics_enabled).and_return(metrics_enabled)
    assign(:importer, Bulkrax::Importer.new)
    render template: 'bulkrax/guided_imports/new'
  end

  context 'when metrics are enabled' do
    let(:metrics_enabled) { true }

    it 'renders the metrics endpoint, a metrics session and the feedback form' do
      expect(page.at_css('.bulk-import-stepper-container')['data-metrics-url']).to eq(Bulkrax::Engine.routes.url_helpers.guided_import_metrics_path)
      expect(page.at_css('#metrics-session-id')['value']).to be_present
      expect(page.css('#seq-feedback input[name="seq_score"]').size).to eq(7)
    end
  end

  context 'when metrics are disabled' do
    let(:metrics_enabled) { false }

    it 'renders no metrics hooks or feedback form' do
      expect(page.at_css('.bulk-import-stepper-container')['data-metrics-url']).to be_nil
      expect(page.at_css('#metrics-session-id')).to be_nil
      expect(page.at_css('#seq-feedback')).to be_nil
    end
  end
end
