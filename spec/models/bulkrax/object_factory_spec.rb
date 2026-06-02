# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  # NOTE: Unable to put this file in spec/factories/bulkrax (where it would mirror the path in app/) because
  # (presumably) FactoryBot autoloads all files in spec/factories, which would always run this spec.
  # Why aren't there more tests?  In part because so much of the ObjectFactory require that we boot
  # up Fedora and SOLR; something that remains non-desirous due to speed.

  RSpec.describe ObjectFactory do
    subject(:object_factory) { build(:object_factory) }

    describe '.search_by_property' do
      let(:collections) do
        [
          FactoryBot.build(:collection, title: ["Specific Title"]),
          FactoryBot.build(:collection, title: ["Title"])
        ]
      end
      let(:klass) { double(where: collections) }

      it 'does find the collection with a partial match' do
        collection = described_class.search_by_property(value: "Title", field: :title, klass: klass)
        expect(collection.title).to eq(["Title"])
      end
    end
    describe 'is capable of looking up records dynamically' do
      include_examples 'dynamic record lookup'
    end

    describe '#update_file_set' do
      let(:factory) { build(:object_factory) }
      let(:file_set) { double('FileSet', label: nil, import_url: nil) }
      let(:actor) { instance_double(::Hyrax::Actors::FileSetActor, file_set: file_set, update_metadata: true) }
      let(:remote_file) { { 'url' => 'https://example.com/foo.tif', 'file_name' => 'foo.tif' } }
      let(:attrs) { { 'remote_files' => [remote_file] } }

      before do
        allow(::Hyrax::Actors::FileSetActor).to receive(:new).and_return(actor)
        allow(factory).to receive(:object).and_return(double(attributes: {}))
        allow(factory).to receive(:file_set_operation_for).and_return(double)
        allow(ImportUrlJob).to receive(:perform_now)
      end

      it 'sets import_url and label on the file_set before ImportUrlJob runs' do
        captured_import_url = nil
        captured_label = nil
        allow(ImportUrlJob).to receive(:perform_now) do |fs, _op, _hdrs|
          captured_import_url = fs.import_url
          captured_label = fs.label
        end
        allow(file_set).to receive(:label=) { |v| allow(file_set).to receive(:label).and_return(v) }
        allow(file_set).to receive(:import_url=) { |v| allow(file_set).to receive(:import_url).and_return(v) }

        factory.send(:update_file_set, attrs)

        expect(captured_import_url).to eq('https://example.com/foo.tif')
        expect(captured_label).to eq('foo.tif')
      end
    end

    describe '#create_file_set_actor' do
      let(:factory) { build(:object_factory) }
      let(:file_set) { double('FileSet') }
      let(:actor) do
        instance_double(::Hyrax::Actors::FileSetActor,
                        file_set: file_set,
                        create_metadata: true,
                        attach_to_work: true)
      end
      let(:work) { double('Work') }
      let(:remote_file) { { 'url' => 'https://example.com/bar.tif', 'file_name' => 'bar.tif' } }

      before do
        allow(::Hyrax::Actors::FileSetActor).to receive(:new).and_return(actor)
        allow(file_set).to receive(:permissions_attributes=)
        allow(factory).to receive(:object).and_return(double)
        allow(factory).to receive(:file_set_operation_for).and_return(double)
        allow(ImportUrlJob).to receive(:perform_now)
      end

      it 'assigns import_url and label before attach_to_work so a Hyrax reload cannot drop them' do
        call_order = []
        allow(file_set).to receive(:import_url=) { call_order << :import_url= }
        allow(file_set).to receive(:label=)      { call_order << :label= }
        allow(actor).to receive(:attach_to_work) { call_order << :attach_to_work }
        allow(ImportUrlJob).to receive(:perform_now) { call_order << :import_url_job }

        factory.send(:create_file_set_actor, {}, work, [], nil, remote_file)

        expect(call_order.index(:import_url=)).to be < call_order.index(:attach_to_work)
        expect(call_order.index(:label=)).to be < call_order.index(:attach_to_work)
        expect(call_order.last).to eq(:import_url_job)
      end
    end

    describe "#transform_attributes" do
      context 'default behavior' do
        it "does not empty arrays that only have empty values" do
          attributes = { empty_array: ["", ""], empty_string: "", filled_array: ["A", "B"], filled_string: "A" }
          factory = described_class.new(attributes: attributes,
                                        source_identifier_value: 123,
                                        work_identifier: "filled_string",
                                        work_identifier_search_field: 'filled_string_sim')
          factory.base_permitted_attributes = %i[empty_array empty_string filled_array filled_string]
          expect(factory.send(:transform_attributes)).to eq(attributes.stringify_keys)
        end
      end

      context 'when :transformation_removes_blank_hash_values = true' do
        it "empties arrays that only have empty values" do
          attributes = { empty_array: ["", ""], empty_string: "", filled_array: ["A", "B"], filled_string: "A" }
          factory = described_class.new(attributes: attributes,
                                        source_identifier_value: 123,
                                        work_identifier: "filled_string",
                                        work_identifier_search_field: 'filled_string_sim')
          factory.base_permitted_attributes = %i[empty_array empty_string filled_array filled_string]
          factory.transformation_removes_blank_hash_values = true
          expect(factory.send(:transform_attributes))
            .to eq({ empty_array: [], empty_string: nil, filled_array: ["A", "B"], filled_string: "A" }.stringify_keys)
        end
      end
    end
  end
end
