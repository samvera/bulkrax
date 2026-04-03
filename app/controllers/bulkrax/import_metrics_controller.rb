# frozen_string_literal: true

module Bulkrax
  class ImportMetricsController < ::Bulkrax::ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    with_themed_layout 'dashboard' if defined?(::Hyrax)

    before_action :authenticate_user!, only: [:index, :export]
    before_action :check_permissions,  only: [:index, :export]

    # POST /importers/guided_import/metrics
    # sendBeacon endpoint — no CSRF, no auth, fire-and-forget.
    skip_before_action :verify_authenticity_token, only: [:record_metric]

    def record_metric
      Bulkrax::ImportMetric.record(
        metric_type: params[:metric_type],
        event:       params[:event],
        user:        current_user,
        session_id:  params[:session_id],
        payload:     (params[:payload] || {}).to_unsafe_h
      )
      head :no_content
    end

    def index
      @aggregator = MetricsAggregator.new(from: date_from, to: date_to)
      @date_from   = date_from
      @date_to     = date_to
    end

    def export
      aggregator = MetricsAggregator.new(from: date_from, to: date_to)
      csv_data    = generate_csv(aggregator)
      send_data csv_data,
                filename:    "bulkrax_import_metrics_#{Date.today.iso8601}.csv",
                type:        'text/csv',
                disposition: 'attachment'
    end

    private

    def date_from
      params[:from].present? ? Date.parse(params[:from]).beginning_of_day : 30.days.ago
    rescue Date::Error
      30.days.ago
    end

    def date_to
      params[:to].present? ? Date.parse(params[:to]).end_of_day : Time.current
    rescue Date::Error
      Time.current
    end

    def check_permissions
      authorize! :read, :admin_dashboard if defined?(CanCan)
    end

    def generate_csv(aggregator)
      CSV.generate do |csv|
        csv << %w[id metric_type event importer_id user_id session_id created_at payload]
        aggregator.export_rows.each { |row| csv << row.values }
      end
    end
  end
end
