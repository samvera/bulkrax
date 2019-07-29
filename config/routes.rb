Bulkrax::Engine.routes.draw do
  resources :exporters do
    get :download
  end
  resources :importers do
    collection do
      post :external_sets
    end
  end
end
