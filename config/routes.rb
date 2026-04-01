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

  scope '/importers' do
    get  'new/guided_import',          to: 'guided_imports#new',      as: :guided_import_new
    post 'guided_import',              to: 'guided_imports#create',   as: :guided_import_create
    post 'guided_import/validate',     to: 'guided_imports#validate', as: :guided_import_validate
    get  'guided_import/download_validation_errors', to: 'guided_imports#download_validation_errors', as: :guided_import_download_validation_errors
    get 'guided_import/demo_scenarios', to: 'guided_imports#demo_scenarios', as: :guided_import_demo_scenarios if Bulkrax.config.guided_import_demo_scenarios_enabled
  end

  resources :importers do
    put :continue
    get :original_file
    get :entry_table
    get :export_errors
    collection do
      get :importer_table
      post :external_sets
      get :sample_csv_file
    end
    resources :entries, only: %i[show update destroy]
    get :upload_corrected_entries
    post :upload_corrected_entries_file
  end
end
