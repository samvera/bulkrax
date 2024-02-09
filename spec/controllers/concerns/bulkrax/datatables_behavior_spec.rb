require 'rails_helper'

RSpec.describe Bulkrax::ImportersController, type: :controller do
  before do
    module Bulkrax::Auth
      def authenticate_user!
        @current_user = User.first
        true
      end

      def current_user
        @current_user
      end
    end
    described_class.prepend Bulkrax::Auth
    allow(Bulkrax::ImporterJob).to receive(:perform_later).and_return(true)
  end

  controller do
    include Bulkrax::DatatablesBehavior
  end

  describe '#table_per_page' do
    it 'returns 30 when params[:length] is less than 1' do
      get :index, params: { length: '0' }
      expect(controller.table_per_page).to eq(30)
    end

    it 'returns params[:length] when it is greater than 0' do
      get :index, params: { length: '10' }
      expect(controller.table_per_page).to eq(10)
    end
  end

  describe '#order_value' do
    it 'returns the value of the specified column' do
      get :index, params: { columns: { '0' => { data: 'some_data' } } }
      expect(controller.order_value('0')).to eq('some_data')
    end
  end

  describe '#table_order' do
    it 'returns the order value and direction' do
      get :index, params: { order: { '0' => { column: '0', dir: 'asc' } }, columns: { '0' => { data: 'some_data' } } }
      expect(controller.table_order).to eq('some_data asc')
    end
  end

  describe '#table_page' do
    it 'returns 1 when params[:start] is blank' do
      get :index, params: { start: '' }
      expect(controller.table_page).to eq(1)
    end

    it 'returns the page number when params[:start] is not blank' do
      get :index, params: { start: '10', length: '5' }
      expect(controller.table_page).to eq(3)
    end
  end

  describe '#table_search' do
    it 'returns false when params[:search][:value] is blank' do
      get :index, params: { search: { value: '' } }
      expect(controller.table_search).to eq(false)
    end

    it 'returns a Arel::Nodes::Grouping node when params[:search][:value] is not blank' do
      get :index, params: { search: { value: 'some_value' } }
      expect(controller.table_search).to be_a(Arel::Nodes::Grouping)
    end
  end

  describe '#format_entries' do
    let(:item) { FactoryBot.create(:bulkrax_importer) }
    let(:entry_1) { FactoryBot.create(:bulkrax_entry, importerexporter: item) }
    let(:entry_2) { FactoryBot.create(:bulkrax_entry, importerexporter: item) }
    let(:entries) { [entry_1, entry_2] }

    it 'returns a hash with the correct structure' do
      get :index
      result = controller.format_entries(entries, item)
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(:data, :recordsTotal, :recordsFiltered)
      expect(result[:data]).to be_a(Array)
      expect(result[:data].first.keys).to contain_exactly(:identifier, :id, :status_message, :type, :updated_at, :errors, :actions)
    end

    it 'returns the correct number of entries' do
      get :index
      result = controller.format_entries(entries, item)
      expect(result[:recordsTotal]).to eq(entries.size)
      expect(result[:recordsFiltered]).to eq(entries.size)
    end
  end

  describe '#util_links' do
    include Bulkrax::Engine.routes.url_helpers

    let(:item) { FactoryBot.create(:bulkrax_importer) }
    let(:entry) { FactoryBot.create(:bulkrax_entry, importerexporter: item) }

    it 'returns a string of HTML links' do
      get :index
      result = controller.util_links(entry, item)
      expect(result).to be_a(String)
      expect(result).to include('glyphicon-info-sign')
      expect(result).to include('glyphicon-repeat')
      expect(result).to include('glyphicon-trash')
    end

    it 'includes a link to the entry' do
      get :index
      result = controller.util_links(entry, item)
      expect(result).to include(importer_entry_path(item, entry))
    end

    it 'includes a delete link to the entry' do
      get :index
      result = controller.util_links(entry, item)
      expect(result).to include(importer_entry_path(item, entry))
      expect(result).to include('method="delete"')
    end
  end

  describe '#entry_status' do
    let(:item) { FactoryBot.create(:bulkrax_importer) }

    it 'returns a string of HTML with a green checkmark when status_message is "Complete"' do
      entry = FactoryBot.create(:bulkrax_entry, importerexporter: item, status_message: 'Complete')
      get :index
      result = controller.entry_status(entry)
      expect(result).to include('<span class=\'glyphicon glyphicon-ok\' style=\'color: green;\'></span> Complete')
    end

    it 'returns a string of HTML with a blue "horizontal ellipsis" icon when status_message is "Pending"' do
      entry = FactoryBot.create(:bulkrax_entry, importerexporter: item, status_message: 'Pending')
      get :index
      result = controller.entry_status(entry)
      expect(result).to include('<span class=\'glyphicon glyphicon-option-horizontal\' style=\'color: blue;\'></span> Pending')
    end

    it 'returns a string of HTML with a red "remove" icon when status_message is neither "Complete" nor "Pending"' do
      entry = FactoryBot.create(:bulkrax_entry, importerexporter: item, status_message: 'Error')
      get :index
      result = controller.entry_status(entry)
      expect(result).to include('<span class=\'glyphicon glyphicon-remove\' style=\'color: red;\'></span> Error')
    end

    it 'returns a string of HTML with a red "remove" icon when status_message is "Deleted"' do
      entry = FactoryBot.create(:bulkrax_entry, importerexporter: item, status_message: 'Deleted')
      get :index
      result = controller.entry_status(entry)
      expect(result).to include('<span class=\'glyphicon glyphicon-remove\' style=\'color: red;\'></span> Deleted')
    end
  end
end
