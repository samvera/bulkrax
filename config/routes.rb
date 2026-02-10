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
      get 'new/v2', action: :new_v2, as: :new_v2
      post 'v2', action: :create_v2, as: :v2
      post 'v2/validate', action: :validate_v2, as: :validate_v2
      get :importer_table
      post :external_sets
      post :sample_csv_file
    end
    resources :entries, only: %i[show update destroy]
    get :upload_corrected_entries
    post :upload_corrected_entries_file
  end
end
