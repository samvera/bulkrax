# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CsvValidationService::FilePathGenerator do
  describe '.default_path' do
    let(:admin_set_id) { nil }
    let(:timestamp) { '20260223_120000' }

    before do
      allow(described_class).to receive(:timestamp).and_return(timestamp)
      allow(FileUtils).to receive(:mkdir_p)
    end

    context 'when no admin_set_id, context, or tenant is provided' do
      it 'generates a basic filename with only timestamp' do
        path = described_class.default_path(admin_set_id)
        expect(path.to_s).to end_with("#{described_class::TEMPLATE_PREFIX}_#{timestamp}.csv")
      end
    end

    context 'when admin_set_id is provided with context' do
      let(:admin_set_id) { 'admin_set_123' }
      let(:admin_set) { double('AdminSet', contexts: ['work']) }

      before do
        allow(Bulkrax.object_factory).to receive(:find).with(admin_set_id).and_return(admin_set)
        allow(admin_set).to receive(:respond_to?).with(:contexts).and_return(true)
      end

      context 'without tenant' do
        before do
          apartment_module = Module.new do
            def self.current
              nil
            end
          end
          stub_const('Apartment::Tenant', apartment_module)
        end

        it 'includes context in the filename' do
          path = described_class.default_path(admin_set_id)
          expect(path.to_s).to end_with("#{described_class::TEMPLATE_PREFIX}_context-work_#{timestamp}.csv")
        end
      end

      context 'with tenant' do
        let(:tenant_id) { 'tenant_abc' }
        let(:account_name) { 'tenant_abc' }
        let(:account) { double('Account', name: account_name) }

        before do
          # Capture let variables for use in closures
          captured_tenant_id = tenant_id
          captured_account = account

          apartment_module = Module.new do
            define_singleton_method(:current) { captured_tenant_id }
          end
          account_class = Class.new do
            define_singleton_method(:find_by) { |_args| captured_account }
          end
          stub_const('Apartment::Tenant', apartment_module)
          stub_const('Account', account_class)
        end

        it 'includes both context and tenant in the filename' do
          path = described_class.default_path(admin_set_id)
          expect(path.to_s).to end_with("#{described_class::TEMPLATE_PREFIX}_context-work_tenant-#{account_name}_#{timestamp}.csv")
        end
      end
    end

    context 'when only tenant is available (no admin_set_id)' do
      let(:tenant_id) { 'tenant_xyz' }
      let(:account_name) { 'tenant_xyz' }
      let(:account) { double('Account', name: account_name) }

      before do
        # Capture let variables for use in closures
        captured_tenant_id = tenant_id
        captured_account = account

        apartment_module = Module.new do
          define_singleton_method(:current) { captured_tenant_id }
        end
        account_class = Class.new do
          define_singleton_method(:find_by) { |_args| captured_account }
        end
        stub_const('Apartment::Tenant', apartment_module)
        stub_const('Account', account_class)
      end

      it 'includes only tenant in the filename' do
        path = described_class.default_path(admin_set_id)
        expect(path.to_s).to end_with("#{described_class::TEMPLATE_PREFIX}_tenant-#{account_name}_#{timestamp}.csv")
      end
    end

    context 'when Apartment::Tenant is not defined' do
      let(:admin_set_id) { 'admin_set_123' }
      let(:admin_set) { double('AdminSet', contexts: ['work']) }

      before do
        allow(Bulkrax.object_factory).to receive(:find).with(admin_set_id).and_return(admin_set)
        allow(admin_set).to receive(:respond_to?).with(:contexts).and_return(true)
        hide_const('Apartment::Tenant')
      end

      it 'does not error and omits tenant from filename' do
        path = described_class.default_path(admin_set_id)
        expect(path.to_s).to end_with("#{described_class::TEMPLATE_PREFIX}_context-work_#{timestamp}.csv")
      end
    end

    context 'when Account is not defined' do
      let(:admin_set_id) { 'admin_set_123' }
      let(:admin_set) { double('AdminSet', contexts: ['work']) }

      before do
        allow(Bulkrax.object_factory).to receive(:find).with(admin_set_id).and_return(admin_set)
        allow(admin_set).to receive(:respond_to?).with(:contexts).and_return(true)
        apartment_module = Module.new do
          def self.current
            'some_tenant'
          end
        end
        stub_const('Apartment::Tenant', apartment_module)
        hide_const('Account')
      end

      it 'does not error and omits tenant from filename' do
        path = described_class.default_path(admin_set_id)
        expect(path.to_s).to end_with("#{described_class::TEMPLATE_PREFIX}_context-work_#{timestamp}.csv")
      end
    end

    context 'when admin_set does not respond to contexts' do
      let(:admin_set_id) { 'admin_set_123' }
      let(:admin_set) { double('AdminSet') }

      before do
        allow(Bulkrax.object_factory).to receive(:find).with(admin_set_id).and_return(admin_set)
        allow(admin_set).to receive(:respond_to?).with(:contexts).and_return(false)
      end

      it 'omits context from filename' do
        path = described_class.default_path(admin_set_id)
        expect(path.to_s).to end_with("#{described_class::TEMPLATE_PREFIX}_#{timestamp}.csv")
      end
    end

    it 'creates the directory if it does not exist' do
      path = described_class.default_path(admin_set_id)
      expect(FileUtils).to have_received(:mkdir_p).with(path.dirname.to_s)
    end
  end

  describe '.load_context' do
    context 'when admin_set_id is nil' do
      it 'returns nil' do
        expect(described_class.load_context(nil)).to be_nil
      end
    end

    context 'when admin_set_id is present' do
      let(:admin_set_id) { 'admin_set_123' }
      let(:admin_set) { double('AdminSet') }

      before do
        allow(Bulkrax.object_factory).to receive(:find).with(admin_set_id).and_return(admin_set)
      end

      context 'when admin_set responds to contexts' do
        before do
          allow(admin_set).to receive(:respond_to?).with(:contexts).and_return(true)
          allow(admin_set).to receive(:contexts).and_return(['work', 'collection'])
        end

        it 'returns the first context' do
          expect(described_class.load_context(admin_set_id)).to eq('work')
        end
      end

      context 'when admin_set does not respond to contexts' do
        before do
          allow(admin_set).to receive(:respond_to?).with(:contexts).and_return(false)
        end

        it 'returns nil' do
          expect(described_class.load_context(admin_set_id)).to be_nil
        end
      end
    end
  end

  describe '.load_tenant' do
    context 'when Apartment::Tenant is not defined' do
      before do
        hide_const('Apartment::Tenant')
      end

      it 'returns nil' do
        expect(described_class.load_tenant).to be_nil
      end
    end

    context 'when Account is not defined' do
      before do
        stub_const('Apartment::Tenant', Class.new)
        hide_const('Account')
      end

      it 'returns nil' do
        expect(described_class.load_tenant).to be_nil
      end
    end

    context 'when both Apartment::Tenant and Account are defined' do
      context 'when tenant_id is nil' do
        before do
          apartment_module = Module.new do
            def self.current
              nil
            end
          end
          stub_const('Apartment::Tenant', apartment_module)
          stub_const('Account', Class.new)
        end

        it 'returns nil' do
          expect(described_class.load_tenant).to be_nil
        end
      end

      context 'when tenant_id is present' do
        let(:tenant_id) { 'tenant_123' }
        let(:account_name) { 'account_name_123' }
        let(:account) { double('Account', name: account_name) }

        before do
          # Capture let variables for use in closures
          captured_tenant_id = tenant_id
          captured_account = account

          apartment_module = Module.new do
            define_singleton_method(:current) { captured_tenant_id }
          end
          account_class = Class.new do
            define_singleton_method(:find_by) { |_args| captured_account }
          end
          stub_const('Apartment::Tenant', apartment_module)
          stub_const('Account', account_class)
        end

        it 'returns the account name' do
          expect(described_class.load_tenant).to eq(account_name)
        end
      end
    end
  end

  describe '.build_filename' do
    let(:timestamp) { '20260223_120000' }

    before do
      allow(described_class).to receive(:timestamp).and_return(timestamp)
    end

    context 'with no context or tenant' do
      it 'returns basic filename' do
        filename = described_class.build_filename(nil, nil)
        expect(filename).to eq("#{described_class::TEMPLATE_PREFIX}_#{timestamp}.csv")
      end
    end

    context 'with context only' do
      it 'includes context in filename' do
        filename = described_class.build_filename('work', nil)
        expect(filename).to eq("#{described_class::TEMPLATE_PREFIX}_context-work_#{timestamp}.csv")
      end
    end

    context 'with tenant only' do
      let(:tenant) { 'tenant_abc' }

      it 'includes tenant in filename' do
        filename = described_class.build_filename(nil, tenant)
        expect(filename).to eq("#{described_class::TEMPLATE_PREFIX}_tenant-#{tenant}_#{timestamp}.csv")
      end
    end

    context 'with both context and tenant' do
      let(:tenant) { 'tenant_xyz' }

      it 'includes both in filename' do
        filename = described_class.build_filename('work', tenant)
        expect(filename).to eq("#{described_class::TEMPLATE_PREFIX}_context-work_tenant-#{tenant}_#{timestamp}.csv")
      end
    end
  end

  describe '.timestamp' do
    it 'returns a formatted timestamp' do
      freeze_time = Time.utc(2026, 2, 23, 12, 0, 0)
      allow(Time).to receive(:current).and_return(freeze_time)

      expect(described_class.timestamp).to eq('20260223_120000')
    end
  end
end
