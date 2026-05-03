# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::Ability do
  # Minimal host-app Ability class that includes the concern and supports
  # bulkrax_default_abilities.  This mirrors how a real Hyrax host app would
  # wire things up, without requiring the full Hydra::Ability stack.
  let(:ability_class) do
    Class.new do
      include CanCan::Ability
      include Bulkrax::Ability

      attr_reader :current_user

      def initialize(user, can_import: false, can_export: false, admin_importers: false, admin_exporters: false)
        @current_user    = user
        @can_import      = can_import
        @can_export      = can_export
        @admin_importers = admin_importers
        @admin_exporters = admin_exporters
        bulkrax_default_abilities
      end

      def can_import_works?
        @can_import
      end

      def can_export_works?
        @can_export
      end

      def can_admin_importers?
        @admin_importers
      end

      def can_admin_exporters?
        @admin_exporters
      end
    end
  end

  let(:user)       { FactoryBot.create(:user) }
  let(:other_user) { FactoryBot.create(:user) }

  # Helpers to build ability instances
  def importer_ability(u, **opts)
    ability_class.new(u, can_import: true, **opts)
  end

  def exporter_ability(u, **opts)
    ability_class.new(u, can_export: true, **opts)
  end

  def admin_importer_ability(u)
    ability_class.new(u, can_import: true, admin_importers: true)
  end

  def admin_exporter_ability(u)
    ability_class.new(u, can_import: true, admin_exporters: true)
  end

  # ------------------------------------------------------------------
  # Predicate defaults
  # ------------------------------------------------------------------

  describe '#can_import_works?' do
    subject(:ability) { ability_class.new(user) }

    it 'returns false by default' do
      expect(ability.can_import_works?).to eq(false)
    end

    it 'can be overridden by a subclass' do
      klass = Class.new(ability_class) do
        def can_import_works?
          true
        end
      end
      expect(klass.new(user).can_import_works?).to eq(true)
    end
  end

  describe '#can_export_works?' do
    subject(:ability) { ability_class.new(user) }

    it 'returns false by default' do
      expect(ability.can_export_works?).to eq(false)
    end
  end

  describe '#can_admin_importers?' do
    subject(:ability) { ability_class.new(user) }

    it 'returns false by default' do
      expect(ability.can_admin_importers?).to eq(false)
    end
  end

  describe '#can_admin_exporters?' do
    subject(:ability) { ability_class.new(user) }

    it 'returns false by default' do
      expect(ability.can_admin_exporters?).to eq(false)
    end
  end

  # ------------------------------------------------------------------
  # bulkrax_default_abilities — no authenticated user
  # ------------------------------------------------------------------

  describe '#bulkrax_default_abilities' do
    context 'when current_user is nil' do
      subject(:ability) { ability_class.new(nil, can_import: true, can_export: true) }

      it 'grants no rules (avoids nil-id bugs)' do
        expect(ability.can?(:create, Bulkrax::Importer)).to eq(false)
        expect(ability.can?(:create, Bulkrax::Exporter)).to eq(false)
      end
    end

    # ------------------------------------------------------------------
    # Importer rules
    # ------------------------------------------------------------------

    describe 'importer rules for a user who can_import_works?' do
      let(:owned_importer)  { FactoryBot.build(:bulkrax_importer, user: user) }
      let(:other_importer)  { FactoryBot.build(:bulkrax_importer, user: other_user) }

      subject(:ability) { importer_ability(user) }

      it { is_expected.to be_able_to(:create, Bulkrax::Importer) }
      it { is_expected.to be_able_to(:read,    owned_importer) }
      it { is_expected.to be_able_to(:update,  owned_importer) }
      it { is_expected.to be_able_to(:destroy, owned_importer) }
      it { is_expected.not_to be_able_to(:read,    other_importer) }
      it { is_expected.not_to be_able_to(:update,  other_importer) }
      it { is_expected.not_to be_able_to(:destroy, other_importer) }
    end

    describe 'importer rules for a user who cannot can_import_works?' do
      subject(:ability) { ability_class.new(user) }

      it { is_expected.not_to be_able_to(:create, Bulkrax::Importer) }
      it { is_expected.not_to be_able_to(:read,   FactoryBot.build(:bulkrax_importer, user: user)) }
    end

    describe 'admin importer rules (can_admin_importers?)' do
      let(:any_importer) { FactoryBot.build(:bulkrax_importer, user: other_user) }

      subject(:ability) { admin_importer_ability(user) }

      it { is_expected.to be_able_to(:manage, any_importer) }
      it { is_expected.to be_able_to(:read,   any_importer) }
      it { is_expected.to be_able_to(:update, any_importer) }
    end

    # ------------------------------------------------------------------
    # Exporter rules
    # ------------------------------------------------------------------

    describe 'exporter rules for a user who can_export_works?' do
      let(:owned_exporter) { FactoryBot.build(:bulkrax_exporter, user: user) }
      let(:other_exporter) { FactoryBot.build(:bulkrax_exporter, user: other_user) }

      subject(:ability) { exporter_ability(user) }

      it { is_expected.to be_able_to(:create, Bulkrax::Exporter) }
      it { is_expected.to be_able_to(:read,    owned_exporter) }
      it { is_expected.to be_able_to(:update,  owned_exporter) }
      it { is_expected.to be_able_to(:destroy, owned_exporter) }
      it { is_expected.not_to be_able_to(:read,    other_exporter) }
      it { is_expected.not_to be_able_to(:update,  other_exporter) }
      it { is_expected.not_to be_able_to(:destroy, other_exporter) }
    end

    describe 'admin exporter rules (can_admin_exporters?)' do
      let(:any_exporter) { FactoryBot.build(:bulkrax_exporter, user: other_user) }

      subject(:ability) { admin_exporter_ability(user) }

      it { is_expected.to be_able_to(:manage, any_exporter) }
    end

    # ------------------------------------------------------------------
    # Entry rules (block-form, checked in Ruby)
    # ------------------------------------------------------------------

    describe 'entry rules for an importer owner' do
      let(:owned_importer)  { FactoryBot.create(:bulkrax_importer, user: user) }
      let(:other_importer)  { FactoryBot.create(:bulkrax_importer, user: other_user) }
      let(:owned_entry)     { FactoryBot.build(:bulkrax_csv_entry, importerexporter: owned_importer) }
      let(:other_entry)     { FactoryBot.build(:bulkrax_csv_entry, importerexporter: other_importer) }

      subject(:ability) { importer_ability(user) }

      it { is_expected.to be_able_to(:read,    owned_entry) }
      it { is_expected.to be_able_to(:update,  owned_entry) }
      it { is_expected.to be_able_to(:destroy, owned_entry) }
      it { is_expected.not_to be_able_to(:read,    other_entry) }
      it { is_expected.not_to be_able_to(:update,  other_entry) }
      it { is_expected.not_to be_able_to(:destroy, other_entry) }
    end

    describe 'entry rules for an exporter owner' do
      let(:owned_exporter) { FactoryBot.create(:bulkrax_exporter, user: user) }
      let(:other_exporter) { FactoryBot.create(:bulkrax_exporter, user: other_user) }
      let(:owned_entry)    { FactoryBot.build(:bulkrax_csv_entry, importerexporter: owned_exporter) }
      let(:other_entry)    { FactoryBot.build(:bulkrax_csv_entry, importerexporter: other_exporter) }

      subject(:ability) { exporter_ability(user) }

      it { is_expected.to be_able_to(:read,    owned_entry) }
      it { is_expected.to be_able_to(:update,  owned_entry) }
      it { is_expected.not_to be_able_to(:read,    other_entry) }
      it { is_expected.not_to be_able_to(:update,  other_entry) }
    end

    # ------------------------------------------------------------------
    # accessible_by scoping (hash-form rules only)
    # ------------------------------------------------------------------

    describe 'accessible_by scoping for Importer' do
      let!(:owned_importer) { FactoryBot.create(:bulkrax_importer, user: user) }
      let!(:other_importer) { FactoryBot.create(:bulkrax_importer, user: other_user) }

      subject(:ability) { importer_ability(user) }

      it 'includes only importers owned by the current user' do
        scope = Bulkrax::Importer.accessible_by(ability)
        expect(scope).to include(owned_importer)
        expect(scope).not_to include(other_importer)
      end
    end

    describe 'accessible_by scoping for Importer (admin)' do
      let!(:owned_importer) { FactoryBot.create(:bulkrax_importer, user: user) }
      let!(:other_importer) { FactoryBot.create(:bulkrax_importer, user: other_user) }

      subject(:ability) { admin_importer_ability(user) }

      it 'includes all importers for an admin' do
        scope = Bulkrax::Importer.accessible_by(ability)
        expect(scope).to include(owned_importer, other_importer)
      end
    end

    describe 'accessible_by scoping for Exporter' do
      let!(:owned_exporter) { FactoryBot.create(:bulkrax_exporter, user: user) }
      let!(:other_exporter) { FactoryBot.create(:bulkrax_exporter, user: other_user) }

      subject(:ability) { exporter_ability(user) }

      it 'includes only exporters owned by the current user' do
        scope = Bulkrax::Exporter.accessible_by(ability)
        expect(scope).to include(owned_exporter)
        expect(scope).not_to include(other_exporter)
      end
    end

    # ------------------------------------------------------------------
    # Action aliases
    # ------------------------------------------------------------------

    describe 'action aliases map custom Bulkrax actions to CRUD equivalents' do
      let(:owned_importer) { FactoryBot.build(:bulkrax_importer, user: user) }

      subject(:ability) { importer_ability(user) }

      it 'maps :entry_table to :read' do
        expect(ability.can?(:entry_table, owned_importer)).to eq(true)
      end

      it 'maps :original_file to :read' do
        expect(ability.can?(:original_file, owned_importer)).to eq(true)
      end

      it 'maps :continue to :update' do
        expect(ability.can?(:continue, owned_importer)).to eq(true)
      end

      it 'maps :export_errors to :read' do
        expect(ability.can?(:export_errors, owned_importer)).to eq(true)
      end

      it 'maps :upload_corrected_entries to :read' do
        expect(ability.can?(:upload_corrected_entries, owned_importer)).to eq(true)
      end

      it 'does not grant custom-action aliases on importers the user does not own' do
        other_importer = FactoryBot.build(:bulkrax_importer, user: other_user)
        expect(ability.can?(:entry_table, other_importer)).to eq(false)
      end
    end
  end
end
