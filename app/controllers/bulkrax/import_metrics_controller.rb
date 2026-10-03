# frozen_string_literal: true

module Bulkrax
  # Receives the metrics the guided import page sends from the browser. Each
  # metric type accepts only its own fields, so the client cannot forge the
  # validation or outcome rows the server records itself.
  class ImportMetricsController < ::Bulkrax::ApplicationController
    before_action :check_metrics_enabled
    before_action :authenticate_user!
    before_action :check_permissions

    STEPS = (1..4).freeze
    RATINGS = (1..7).freeze
    TIMED_STEPS = %w[step1 step2 step3].freeze
    MAX_MILLISECONDS = 2_147_483_647 # largest value a 4-byte integer column holds

    def create
      attributes = client_metric_attributes
      return head :unprocessable_entity unless attributes

      ImportMetric.record(**attributes, user_id: current_user.id, session_id: params[:session_id].to_s.first(64).presence)
      head :no_content
    end

    private

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
