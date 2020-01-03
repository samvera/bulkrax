# frozen_string_literal: true

require_dependency "bulkrax/application_controller"
require_dependency "oai"
require 'fileutils'

module Bulkrax
  class EntriesController < ApplicationController
    include Hyrax::ThemedLayoutController
    before_action :authenticate_user!
    with_themed_layout 'dashboard'

    # GET /importers/1/entries/1
    def show
      @importer = Importer.find(params[:importer_id])
      @entry = Entry.find(params[:id])
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb 'Importers', bulkrax.importers_path
      add_breadcrumb @importer.name, bulkrax.importer_path(@importer.id)
      add_breadcrumb @entry.id
    end

  end
end
