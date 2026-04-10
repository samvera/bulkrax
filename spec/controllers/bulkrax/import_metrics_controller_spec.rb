# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportMetricsController, type: :controller do
    routes { Bulkrax::Engine.routes }

    let(:current_ability) { instance_double(Ability) }
    let(:user) { FactoryBot.create(:user) }

    before do
      user
      module Bulkrax::MetricsAuth
        def authenticate_user!
          @current_user = User.first
          true
        end

        def current_user
          @current_user
        end
      end
      described_class.prepend Bulkrax::MetricsAuth
      allow(current_ability).to receive(:can?).with(:read, :admin_dashboard).and_return(true)
      allow(current_ability).to receive(:authorize!).with(:read, :admin_dashboard).and_return(true)
      allow(controller).to receive(:current_ability).and_return(current_ability)
      allow(Bulkrax.config).to receive(:guided_import_metrics_enabled).and_return(true)
    end

    describe 'POST #record_metric' do
      it 'returns 204 no content' do
        post :record_metric, params: {
          metric_type: 'funnel',
          event: 'step_reached',
          session_id: 'gi_test123',
          payload: { step: 1 }
        }
        expect(response).to have_http_status(:no_content)
      end

      it 'creates an ImportMetric record' do
        expect do
          post :record_metric, params: {
            metric_type: 'funnel',
            event: 'step_reached',
            session_id: 'gi_test123',
            payload: { step: 1 }
          }
        end.to change(ImportMetric, :count).by(1)
      end

      it 'returns 204 even with invalid data' do
        post :record_metric, params: {
          metric_type: 'invalid_type',
          event: 'test'
        }
        expect(response).to have_http_status(:no_content)
      end

      it 'returns 404 when metrics are disabled' do
        allow(Bulkrax.config).to receive(:guided_import_metrics_enabled).and_return(false)
        post :record_metric, params: { metric_type: 'funnel', event: 'test' }
        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'GET #index' do
      it 'renders the dashboard for admin users' do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it 'assigns aggregator and date range' do
        get :index, params: { from: '2026-04-01', to: '2026-04-10' }
        expect(assigns(:aggregator)).to be_a(MetricsAggregator)
        expect(assigns(:date_from)).to be_present
        expect(assigns(:date_to)).to be_present
      end

      it 'defaults to 30-day range when no params given' do
        get :index
        expect(assigns(:date_from)).to be_within(2.seconds).of(30.days.ago)
        expect(assigns(:date_to)).to be_within(2.seconds).of(Time.current)
      end

      it 'handles invalid date params gracefully' do
        get :index, params: { from: 'not-a-date', to: 'also-invalid' }
        expect(response).to have_http_status(:ok)
        expect(assigns(:date_from)).to be_within(2.seconds).of(30.days.ago)
      end

      it 'returns 403 for non-admin users' do
        allow(current_ability).to receive(:can?).with(:read, :admin_dashboard).and_return(false)
        allow(controller).to receive(:authorize!).with(:read, :admin_dashboard).and_raise(CanCan::AccessDenied)
        expect { get :index }.to raise_error(CanCan::AccessDenied)
      end

      it 'returns 404 when metrics are disabled' do
        allow(Bulkrax.config).to receive(:guided_import_metrics_enabled).and_return(false)
        get :index
        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'GET #export' do
      it 'returns a CSV file' do
        get :export
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('text/csv')
      end

      it 'sets the correct filename' do
        get :export
        expect(response.headers['Content-Disposition']).to include("bulkrax_import_metrics_#{Time.zone.today.iso8601}.csv")
      end

      it 'includes CSV headers' do
        get :export
        csv_lines = response.body.split("\n")
        expect(csv_lines.first).to eq('id,metric_type,event,importer_id,user_id,session_id,created_at,payload')
      end

      it 'includes metric data in the CSV' do
        ImportMetric.record(metric_type: 'funnel', event: 'step_reached', payload: { step: 1 })
        get :export
        csv_lines = response.body.split("\n")
        expect(csv_lines.size).to eq(2) # header + 1 data row
      end

      it 'returns 404 when metrics are disabled' do
        allow(Bulkrax.config).to receive(:guided_import_metrics_enabled).and_return(false)
        get :export
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
