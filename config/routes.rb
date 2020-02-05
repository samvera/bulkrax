# frozen_string_literal: true

Bulkrax::Engine.routes.draw do
  resources :exporters do
    get :download
  end
  resources :importers do
    get :export_errors
    collection do
      post :external_sets
    end
    resources :entries, only: %i[show]
  end
end
