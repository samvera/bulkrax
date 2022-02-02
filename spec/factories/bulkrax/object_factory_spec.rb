# frozen_string_literal: true

require 'rails_helper'
require Rails.root.parent.parent.join('spec', 'models', 'concerns', 'bulkrax', 'dynamic_record_lookup_spec').to_s

module Bulkrax
  RSpec.describe ObjectFactory do
    subject(:object_factory) { build(:object_factory) }

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end
  end
end
