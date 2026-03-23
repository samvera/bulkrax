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
    get :original_file
    get :entry_table
    get :export_errors
    collection do
      get 'new/guided_import', action: :guided_import_new, as: :guided_import_new
      post 'guided_import', action: :guided_import_create, as: :guided_import_create
      post 'guided_import/validate', action: :guided_import_validate, as: :guided_import_validate
      get 'guided_import/demo_scenarios', action: :guided_import_demo_scenarios, as: :guided_import_demo_scenarios if Bulkrax.config.guided_import_demo_scenarios_enabled
      get :importer_table
      post :external_sets
      get :sample_csv_file
    end
    resources :entries, only: %i[show update destroy]
    get :upload_corrected_entries
    post :upload_corrected_entries_file
  end
end
