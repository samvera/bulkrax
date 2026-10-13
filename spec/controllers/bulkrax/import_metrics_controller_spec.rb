# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportMetricsController, type: :controller do
    routes { Bulkrax::Engine.routes }

    let(:user) { FactoryBot.create(:user) }
    let(:current_ability) { instance_double(Ability, can_import_works?: can_import) }
    let(:can_import) { true }
    let(:metrics_enabled) { true }
    let(:signed_in) { true }

    before do
      signed_in_user = signed_in ? user : nil
      controller.define_singleton_method(:current_user) { signed_in_user }
      controller.define_singleton_method(:authenticate_user!) { signed_in_user || raise(CanCan::AccessDenied) }
      allow(controller).to receive(:current_ability).and_return(current_ability)
      allow(Bulkrax.config).to receive(:guided_import_metrics_enabled).and_return(metrics_enabled)
    end

    def post_metric(params)
      post :create, params: { session_id: 'session-1' }.merge(params)
    end

    describe 'POST #create' do
      it 'records a funnel step for the signed-in user' do
        post_metric(metric_type: 'funnel', step: '2')

        expect(response).to have_http_status(:no_content)
        expect(ImportMetric.last).to have_attributes(metric_type: 'funnel', event: 'step_reached', step: 2, user_id: user.id, session_id: 'session-1')
      end

      it 'rejects a funnel step outside the wizard' do
        expect { post_metric(metric_type: 'funnel', step: '9') }.not_to change(ImportMetric, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'records session timing, rounding step durations and dropping unknown steps' do
        post_metric(metric_type: 'timing', duration_ms: '90000', step_durations: { step1: '30000', step2: '45000.7', other: 'x' })

        expect(ImportMetric.last).to have_attributes(metric_type: 'timing', event: 'session_complete', duration_ms: 90_000)
        expect(ImportMetric.last.payload).to eq('step1' => 30_000, 'step2' => 45_001)
      end

      it 'rejects a duration that is not a finite number' do
        expect { post_metric(metric_type: 'timing', duration_ms: '1e400') }.not_to change(ImportMetric, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects step durations that are not keyed by step' do
        expect { post_metric(metric_type: 'timing', duration_ms: '1000', step_durations: 'abc') }.not_to change(ImportMetric, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'clamps timing to what the column can hold' do
        post_metric(metric_type: 'timing', duration_ms: '99999999999999', step_durations: { step1: '-12' })
        expect(ImportMetric.last.duration_ms).to eq(2_147_483_647)
        expect(ImportMetric.last.payload).to eq('step1' => 0)
      end

      context 'with feedback' do
        let(:own_importer) { FactoryBot.create(:bulkrax_importer_csv, user: user) }
        let(:other_importer) { FactoryBot.create(:bulkrax_importer_csv) }

        it 'records the rating and comment against an importer the user owns' do
          post_metric(metric_type: 'feedback', rating: '6', comment: 'Smooth', importer_id: own_importer.id)

          expect(ImportMetric.last).to have_attributes(metric_type: 'feedback', event: 'seq_rating', rating: 6, importer_id: own_importer.id)
          expect(ImportMetric.last.payload).to eq('comment' => 'Smooth')
        end

        it 'does not link feedback to an importer the user does not own' do
          post_metric(metric_type: 'feedback', rating: '6', importer_id: other_importer.id)
          expect(ImportMetric.last.importer_id).to be_nil
        end

        it 'truncates long comments' do
          post_metric(metric_type: 'feedback', rating: '6', comment: 'a' * 5000)
          expect(ImportMetric.last.payload['comment'].length).to eq(1000)
        end

        it 'rejects a rating outside the 1 to 7 scale' do
          expect { post_metric(metric_type: 'feedback', rating: '8') }.not_to change(ImportMetric, :count)
        end
      end

      it 'rejects metric types the server records itself' do
        expect { post_metric(metric_type: 'import_outcome', outcome: 'Complete') }.not_to change(ImportMetric, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      context 'when metrics are disabled' do
        let(:metrics_enabled) { false }

        it 'returns not found and records nothing' do
          expect { post_metric(metric_type: 'funnel', step: '1') }.not_to change(ImportMetric, :count)
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when the user is not signed in' do
        let(:signed_in) { false }

        it 'records nothing' do
          expect { post_metric(metric_type: 'funnel', step: '1') }.to raise_error(CanCan::AccessDenied)
          expect(ImportMetric.count).to eq(0)
        end
      end

      context 'when the user cannot import' do
        let(:can_import) { false }

        it 'records nothing' do
          expect { post_metric(metric_type: 'funnel', step: '1') }.to raise_error(CanCan::AccessDenied)
          expect(ImportMetric.count).to eq(0)
        end
      end

      context 'with forgery protection on' do
        before { allow(controller).to receive(:protect_against_forgery?).and_return(true) }

        it 'rejects a request without an authenticity token' do
          expect { post_metric(metric_type: 'funnel', step: '1') }.to raise_error(ActionController::InvalidAuthenticityToken)
        end
      end
    end

    describe 'the dashboard' do
      let(:current_ability) { instance_double(Ability, can_import_works?: true, can_read_bulkrax_metrics?: can_read) }
      let(:can_read) { true }

      describe 'GET #index' do
        it 'summarizes the requested date range' do
          get :index, params: { from: '2026-01-01', to: '2026-01-31' }

          expect(response).to have_http_status(:ok)
          expect(assigns(:aggregator)).to have_attributes(from: Time.zone.parse('2026-01-01'), to: Time.zone.parse('2026-01-31').end_of_day)
        end

        it 'falls back to the last 30 days when the dates cannot be read' do
          get :index, params: { from: 'not-a-date', to: '' }
          expect(assigns(:aggregator).from).to be_within(1.minute).of(30.days.ago.beginning_of_day)
        end

        context 'when the user cannot read metrics' do
          let(:can_read) { false }

          it 'denies access' do
            expect { get :index }.to raise_error(CanCan::AccessDenied)
          end
        end

        context 'when the host app grants no metrics permission at all' do
          let(:current_ability) { instance_double(Ability, can_import_works?: true) }

          it 'denies access' do
            expect { get :index }.to raise_error(CanCan::AccessDenied)
          end
        end

        context 'when metrics are disabled' do
          let(:metrics_enabled) { false }

          it 'returns not found' do
            get :index
            expect(response).to have_http_status(:not_found)
          end
        end
      end

      describe 'GET #export' do
        it 'neutralizes formulas hidden behind a leading tab or carriage return' do
          ImportMetric.record(metric_type: 'funnel', event: 'step_reached', step: 1, session_id: "\t=1+1")
          ImportMetric.record(metric_type: 'funnel', event: 'step_reached', step: 1, session_id: "\r=1+1")
          get :export

          expect(CSV.parse(response.body).drop(1).map { |row| row[6] }).to contain_exactly("'\t=1+1", "'\r=1+1")
        end

        it 'downloads every metric in the range as CSV, neutralizing spreadsheet formulas' do
          ImportMetric.record(metric_type: 'funnel', event: 'step_reached', step: 2, session_id: '=HYPERLINK("x")')
          get :export

          expect(response.media_type).to eq('text/csv')
          rows = CSV.parse(response.body)
          expect(rows.first).to include('metric_type', 'session_id', 'payload')
          expect(rows.second).to include('funnel', %('=HYPERLINK("x")))
        end

        context 'when the user cannot read metrics' do
          let(:can_read) { false }

          it 'denies access' do
            expect { get :export }.to raise_error(CanCan::AccessDenied)
          end
        end
      end
    end
  end
end
