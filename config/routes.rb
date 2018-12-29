Bulkrax::Engine.routes.draw do
  resources :importers do
    collection do
      post :external_sets
    end
  end
end
