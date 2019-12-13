# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ImportersController, type: :routing do
    routes { Bulkrax::Engine.routes }
    describe 'routing' do
      it 'routes to #index' do
        expect(get: '/importers').to route_to('bulkrax/importers#index')
      end

      it 'routes to #new' do
        expect(get: '/importers/new').to route_to('bulkrax/importers#new')
      end

      it 'routes to #show' do
        expect(get: '/importers/1').to route_to('bulkrax/importers#show', id: '1')
      end

      it 'routes to #edit' do
        expect(get: '/importers/1/edit').to route_to('bulkrax/importers#edit', id: '1')
      end

      it 'routes to #create' do
        expect(post: '/importers').to route_to('bulkrax/importers#create')
      end

      it 'routes to #update via PUT' do
        expect(put: '/importers/1').to route_to('bulkrax/importers#update', id: '1')
      end

      it 'routes to #update via PATCH' do
        expect(patch: '/importers/1').to route_to('bulkrax/importers#update', id: '1')
      end

      it 'routes to #destroy' do
        expect(delete: '/importers/1').to route_to('bulkrax/importers#destroy', id: '1')
      end
    end
  end
end
