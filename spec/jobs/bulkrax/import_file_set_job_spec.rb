# frozen_string_literal: true

require 'rails_helper'
require Rails.root.parent.parent.join('spec', 'models', 'concerns', 'bulkrax', 'dynamic_record_lookup_spec').to_s

module Bulkrax
  RSpec.describe ImportFileSetJob, type: :job do
    subject(:import_file_set_job) { described_class.new }
    let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }

    describe 'shared examples' do # TODO: remove or rename
      include_examples 'dynamic record lookup'
    end
  end
end
