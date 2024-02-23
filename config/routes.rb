# frozen_string_literal: true

Bulkrax::Engine.routes.draw do
  resources :exporters do
    get :download
    get :entry_table
    collection do
      get :exporter_table
    end
    resources :entries, only: %i[show update destroy]
  end
  resources :importers do
    put :continue
    get :entry_table
    get :export_errors
    collection do
      get :importer_table
      post :external_sets
    end
    resources :entries, only: %i[show update destroy]
    get :upload_corrected_entries
    post :upload_corrected_entries_file
  end
end
