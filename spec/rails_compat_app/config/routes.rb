# frozen_string_literal: true

Rails.application.routes.draw do
  mount Bulkrax::Engine => '/bulkrax'
end
