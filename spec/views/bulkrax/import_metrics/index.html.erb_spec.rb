# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'bulkrax/import_metrics/index', type: :view do
  let(:importer) { FactoryBot.create(:bulkrax_importer_csv, name: 'Spring photos') }
  let(:page) { Nokogiri::HTML(rendered) }

  before do
    view.extend Bulkrax::Engine.routes.url_helpers
    assign(:aggregator, Bulkrax::MetricsAggregator.new(from: 7.days.ago, to: Time.current.end_of_day))
  end

  context 'with metrics in the range' do
    before do
      Bulkrax::ImportMetric.record(metric_type: 'validation', event: 'validation_complete', outcome: 'fail', session_id: 's1',
                                   duration_ms: 2_500, payload: { error_types: ['missing_files'] })
      Bulkrax::ImportMetric.record(metric_type: 'funnel', event: 'step_reached', step: 1, session_id: 's1')
      Bulkrax::ImportMetric.record(metric_type: 'feedback', event: 'seq_rating', rating: 6, payload: { comment: 'Clear steps' })
      Bulkrax::ImportMetric.record_import_outcome(importer.current_run, importer: importer, outcome: 'Complete', first_attempt: true,
                                                                        session_id: 's1', payload: { total_work_entries: 3, total_file_set_entries: 2 })
      render
    end

    it 'renders every section with translated text' do
      expect(rendered).not_to include('translation_missing')
      expect(page.css('section h2').map(&:text)).to eq(
        ['Imports by Day', 'Validation Accuracy', 'Import Funnel', 'Most Common Validation Errors', 'Ease-of-Use Ratings', 'Recent Guided Imports']
      )
    end

    it 'shows the recorded outcome and record count for each recent import' do
      row = page.at_css('#metrics-recent ~ table tbody tr')
      expect(row.css('td').map { |td| td.text.strip }.first(4)).to eq(['Spring photos', 'Complete', '5', 'Yes'])
    end

    it 'pairs the first attempt with its validation result' do
      expect(page.at_css('#metrics-accuracy ~ table tbody th').text).to eq('Failed validation')
    end
  end

  context 'with no metrics in the range' do
    before { render }

    it 'shows the empty state' do
      expect(rendered).not_to include('translation_missing')
      expect(page.at_css('.metrics-empty h2').text).to eq('No metrics in this date range')
      expect(page.css('section')).to be_empty
    end
  end
end
