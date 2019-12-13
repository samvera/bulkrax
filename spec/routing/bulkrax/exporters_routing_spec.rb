# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe ExportersController, type: :routing do
    routes { Bulkrax::Engine.routes }
    describe 'routing' do
      it 'routes to #index' do
        expect(get: '/exporters').to route_to('bulkrax/exporters#index')
      end

      it 'routes to #new' do
        expect(get: '/exporters/new').to route_to('bulkrax/exporters#new')
      end

      it 'routes to #show' do
        expect(get: '/exporters/1').to route_to('bulkrax/exporters#show', id: '1')
      end

      it 'routes to #edit' do
        expect(get: '/exporters/1/edit').to route_to('bulkrax/exporters#edit', id: '1')
      end

      it 'routes to #create' do
        expect(post: '/exporters').to route_to('bulkrax/exporters#create')
      end

      it 'routes to #update via PUT' do
        expect(put: '/exporters/1').to route_to('bulkrax/exporters#update', id: '1')
      end

      it 'routes to #update via PATCH' do
        expect(patch: '/exporters/1').to route_to('bulkrax/exporters#update', id: '1')
      end

      it 'routes to #destroy' do
        expect(delete: '/exporters/1').to route_to('bulkrax/exporters#destroy', id: '1')
      end
    end
  end
end
