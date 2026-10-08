# frozen_string_literal: true

module Bulkrax
  # Receives the metrics the guided import page sends from the browser, and
  # serves the metrics dashboard. Each browser metric type accepts only its
  # own fields, so the client cannot forge the validation or outcome rows the
  # server records itself.
  class ImportMetricsController < ::Bulkrax::ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    with_themed_layout 'dashboard' if defined?(::Hyrax)

    before_action :check_metrics_enabled
    before_action :authenticate_user!
    before_action :check_permissions, only: :create
    before_action :check_dashboard_permissions, except: :create

    STEPS = (1..4).freeze
    RATINGS = (1..7).freeze
    TIMED_STEPS = %w[step1 step2 step3].freeze
    MAX_MILLISECONDS = 2_147_483_647 # largest value a 4-byte integer column holds
    EXPORT_HEADERS = %w[id metric_type event importer_id importer_run_id user_id session_id outcome
                        first_attempt duration_ms step rating created_at payload].freeze

    def create
      attributes = client_metric_attributes
      return head :unprocessable_entity unless attributes

      ImportMetric.record(**attributes, user_id: current_user.id, session_id: params[:session_id].to_s.first(64).presence)
      head :no_content
    end

    def index
      add_dashboard_breadcrumbs
      @aggregator = MetricsAggregator.new(from: date_param(:from, 30.days.ago).beginning_of_day, to: date_param(:to, Time.current).end_of_day)
    end

    def export
      aggregator = MetricsAggregator.new(from: date_param(:from, 30.days.ago).beginning_of_day, to: date_param(:to, Time.current).end_of_day)
      csv = CSV.generate do |rows|
        rows << EXPORT_HEADERS
        aggregator.each_export_row { |row| rows << row.map { |cell| spreadsheet_safe(cell) } }
      end
      send_data csv, filename: "bulkrax_import_metrics_#{Time.zone.today.iso8601}.csv", type: 'text/csv', disposition: 'attachment'
    end

    private

    def date_param(key, default)
      Time.zone.parse(params[key].to_s) || default
    rescue ArgumentError
      default
    end

    # Session ids and comments come from the browser, so a cell that starts
    # like a formula is prefixed to keep spreadsheets from evaluating it.
    def spreadsheet_safe(cell)
      cell.is_a?(String) && cell.start_with?('=', '+', '-', '@', "\t", "\r") ? "'#{cell}" : cell
    end

    def add_dashboard_breadcrumbs
      return unless defined?(::Hyrax)

      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb t('bulkrax.import_metrics.title')
    end

    def check_dashboard_permissions
      raise CanCan::AccessDenied unless current_ability.respond_to?(:can_read_bulkrax_metrics?) && current_ability.can_read_bulkrax_metrics?
    end

    def client_metric_attributes
      case params[:metric_type]
      when 'funnel'   then funnel_attributes
      when 'timing'   then timing_attributes
      when 'feedback' then feedback_attributes
      end
    end

    def funnel_attributes
      step = params[:step].to_i
      { metric_type: 'funnel', event: 'step_reached', step: step } if STEPS.cover?(step)
    end

    def timing_attributes
      total = milliseconds(params[:duration_ms])
      durations = params.fetch(:step_durations, ActionController::Parameters.new)
      return unless total && durations.is_a?(ActionController::Parameters)

      steps = durations.permit(*TIMED_STEPS).to_h.transform_values { |ms| milliseconds(ms) }
      { metric_type: 'timing', event: 'session_complete', duration_ms: total, payload: steps } unless steps.value?(nil)
    end

    def milliseconds(value)
      ms = Float(value.to_s, exception: false)
      ms.clamp(0, MAX_MILLISECONDS).round if ms&.finite?
    end

    def feedback_attributes
      rating = params[:rating].to_i
      return unless RATINGS.cover?(rating)

      {
        metric_type: 'feedback',
        event: 'seq_rating',
        rating: rating,
        importer_id: Importer.where(id: params[:importer_id], user_id: current_user.id).pick(:id),
        payload: { comment: params[:comment].to_s.first(1000) }
      }
    end

    def check_metrics_enabled
      head :not_found unless Bulkrax.config.guided_import_metrics_enabled
    end

    def check_permissions
      raise CanCan::AccessDenied unless current_ability.can_import_works?
    end
  end
end
