# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  # NOTE: Unable to put this file in spec/factories/bulkrax (where it would mirror the path in app/) because
  # (presumably) FactoryBot autoloads all files in spec/factories, which would always run this spec.
  RSpec.describe ObjectFactory do
    subject(:object_factory) { build(:object_factory) }

    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end
  end
end
