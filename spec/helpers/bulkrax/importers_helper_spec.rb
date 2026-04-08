# frozen_string_literal: true

require 'rails_helper'

# Specs in this file have access to a helper object that includes
# the ImportersHelper. For example:
#
# describe ImportersHelper do
#   describe "string concat" do
#     it "concats two strings with spaces" do
#       expect(helper.concat_strings("this","that")).to eq("this that")
#     end
#   end
# end
module Bulkrax
  RSpec.describe ImportersHelper, type: :helper do
    describe '#available_admin_sets' do
      let(:admin_set_id) { 'admin_set_1' }
      let(:admin_set) { instance_double('AdminSet', title: ['My Admin Set']) }

      before do
        allow(helper).to receive(:current_ability).and_return(instance_double('Ability'))
        allow(Hyrax::Collections::PermissionsService).to receive(:source_ids_for_deposit)
          .with(ability: helper.current_ability, source_type: 'admin_set')
          .and_return([admin_set_id])
        allow(Bulkrax.object_factory).to receive(:find_or_nil).with(admin_set_id).and_return(admin_set)
      end

      it 'returns an array of [title, id] pairs for admin sets the user can deposit to' do
        expect(helper.available_admin_sets).to eq([['My Admin Set', admin_set_id]])
      end

      it 'memoizes the result' do
        helper.available_admin_sets
        helper.available_admin_sets
        expect(Hyrax::Collections::PermissionsService).to have_received(:source_ids_for_deposit).once
      end

      context 'when admin set has no title' do
        let(:admin_set) { nil }

        it 'falls back to the id' do
          expect(helper.available_admin_sets).to eq([[admin_set_id, admin_set_id]])
        end
      end
    end
  end
end
