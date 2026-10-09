# frozen_string_literal: true

require 'rails_helper'
require_relative '../../shared/serialized_attributes'

RSpec.describe 'Bulkrax serialization with Hyrax' do
  include_examples 'persisted Bulkrax serialization'
end
