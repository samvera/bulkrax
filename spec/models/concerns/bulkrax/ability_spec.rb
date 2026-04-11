# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::Ability do
  # Minimal host-app Ability class that includes the concern
  let(:ability_class) do
    Class.new do
      include Bulkrax::Ability
    end
  end

  subject(:ability) { ability_class.new }

  describe '#can_import_works?' do
    it 'returns false by default' do
      expect(ability.can_import_works?).to eq(false)
    end

    it 'can be overridden by a subclass' do
      klass = Class.new do
        include Bulkrax::Ability

        def can_import_works?
          true
        end
      end
      expect(klass.new.can_import_works?).to eq(true)
    end
  end

  describe '#can_export_works?' do
    it 'returns false by default' do
      expect(ability.can_export_works?).to eq(false)
    end

    it 'can be overridden by a subclass' do
      klass = Class.new do
        include Bulkrax::Ability

        def can_export_works?
          true
        end
      end
      expect(klass.new.can_export_works?).to eq(true)
    end
  end

  describe '#can_admin_importers?' do
    it 'returns false by default' do
      expect(ability.can_admin_importers?).to eq(false)
    end

    it 'can be overridden by a subclass' do
      klass = Class.new do
        include Bulkrax::Ability

        def can_admin_importers?
          true
        end
      end
      expect(klass.new.can_admin_importers?).to eq(true)
    end
  end

  describe '#can_admin_exporters?' do
    it 'returns false by default' do
      expect(ability.can_admin_exporters?).to eq(false)
    end

    it 'can be overridden by a subclass' do
      klass = Class.new do
        include Bulkrax::Ability

        def can_admin_exporters?
          true
        end
      end
      expect(klass.new.can_admin_exporters?).to eq(true)
    end
  end
end
