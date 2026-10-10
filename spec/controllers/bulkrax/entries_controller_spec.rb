# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe EntriesController, type: :controller do
    routes { Bulkrax::Engine.routes }

    let(:admin_user) { FactoryBot.create(:user) }
    let(:owner) { FactoryBot.create(:user) }
    let(:current_run) { double(id: 1) }

    let(:ability_class) do
      Class.new do
        include CanCan::Ability
        include Bulkrax::Ability

        attr_reader :current_user

        def initialize(user, admin_importers: false, admin_exporters: false)
          @current_user = user
          @admin_importers = admin_importers
          @admin_exporters = admin_exporters
          bulkrax_default_abilities
        end

        def can_import_works?
          false
        end

        def can_export_works?
          false
        end

        def can_admin_importers?
          @admin_importers
        end

        def can_admin_exporters?
          @admin_exporters
        end
      end
    end

    before do
      module Bulkrax::Auth
        def authenticate_user!
          @current_user = User.first
          true
        end

        def current_user
          @current_user
        end
      end
      described_class.prepend Bulkrax::Auth
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(ScheduleRelationshipsJob).to receive(:set)
        .with(wait: 5.minutes).and_return(double(perform_later: true))
      allow(Bulkrax::ImportWorkJob).to receive(:perform_later).and_return(true)
    end

    shared_examples 'an entry admin' do
      let(:entry) { FactoryBot.create(:bulkrax_csv_entry, importerexporter: parent) }

      before do
        allow(controller).to receive(:current_ability).and_return(ability)
        allow(parent).to receive(:current_run).with(skip_counts: true).and_return(current_run)
        allow(entry).to receive(:set_status_info)
        allow(entry).to receive(:factory).and_return(nil)
      end

      it 'shows an entry owned by another user' do
        get :show, params: entry_params

        expect(response).to be_successful
      end

      it 're-runs an entry owned by another user' do
        patch :update, params: entry_params

        expect(response).to redirect_to(entry_path)
      end

      it 'deletes an entry owned by another user' do
        delete :destroy, params: entry_params

        expect(response).to redirect_to(entry_path)
      end
    end

    context 'when the user administers importers' do
      let(:parent) { FactoryBot.create(:bulkrax_importer, user: owner) }
      let(:ability) { ability_class.new(admin_user, admin_importers: true) }
      let(:entry_params) { { importer_id: parent.to_param, id: entry.to_param } }
      let(:entry_path) { importer_entry_path(parent, entry) }

      include_examples 'an entry admin'
    end

    context 'when the user administers exporters' do
      let(:parent) { FactoryBot.create(:bulkrax_exporter, user: owner) }
      let(:ability) { ability_class.new(admin_user, admin_exporters: true) }
      let(:entry_params) { { exporter_id: parent.to_param, id: entry.to_param } }
      let(:entry_path) { exporter_entry_path(parent, entry) }

      include_examples 'an entry admin'
    end
  end
end
