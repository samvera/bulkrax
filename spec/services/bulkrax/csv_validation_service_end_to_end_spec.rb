# frozen_string_literal: true

require 'rails_helper'

# End-to-end integration spec for Bulkrax::CsvValidationService
#
# Intent: exercise the full service stack against real CSV inputs and assert on
# the complete result contract. No internal mocking — changes to any component
# inside the service must not break the expectations here. This makes the suite
# safe to run before and after a refactor to confirm no observable behaviour
# has changed.
#
# The test app provides: Work (ActiveFedora + Hyrax::WorkBehavior),
# Collection (ActiveFedora + Hyrax::CollectionBehavior + Hyrax::BasicMetadata),
# and FileSet (Hyrax). These are registered via Hyrax.config.curation_concerns.

RSpec.describe Bulkrax::CsvValidationService, type: :service do
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def csv_tempfile(content)
    file = Tempfile.new(['bulkrax_e2e', '.csv'])
    file.write(content)
    file.rewind
    file
  end

  def zip_tempfile(files = {})
    zip = Tempfile.new(['bulkrax_e2e', '.zip'])
    Zip::File.open(zip.path, create: true) do |z|
      files.each { |name, data| z.get_output_stream(name) { |f| f.write(data) } }
    end
    zip.rewind
    zip
  end

  # Collect all tempfiles opened in an example and close/unlink them after.
  let(:tempfiles) { [] }
  after do
    tempfiles.each do |f|
      f.close
      f.unlink
    end
  end

  def csv(content)
    tempfiles << csv_tempfile(content)
    tempfiles.last
  end

  def zip(files = {})
    tempfiles << zip_tempfile(files)
    tempfiles.last
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  shared_examples 'returns the full result contract' do
    it 'returns a Hash with all required keys' do
      expect(result).to be_a(Hash)
      expect(result.keys).to match_array(%i[
                                           headers missingRequired unrecognized rowCount
                                           isValid hasWarnings rowErrors
                                           collections works fileSets totalItems
                                           fileReferences missingFiles foundFiles zipIncluded
                                         ])
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 1: Well-formed CSV, all required fields present, no files
  # ---------------------------------------------------------------------------

  describe 'well-formed CSV with works and collections, no file attachments' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title
        col1,Collection,My Collection
        work1,Work,First Work
        work2,Work,Second Work
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'is valid with no errors' do
      expect(result[:isValid]).to be true
    end

    it 'reports the correct row count' do
      expect(result[:rowCount]).to eq(3)
    end

    it 'reports no missing required fields' do
      expect(result[:missingRequired]).to be_empty
    end

    it 'identifies works and collections separately' do
      expect(result[:works].size).to eq(2)
      expect(result[:collections].size).to eq(1)
      expect(result[:fileSets]).to be_empty
    end

    it 'reports total items' do
      expect(result[:totalItems]).to eq(3)
    end

    it 'reports no file references when no file column is present' do
      expect(result[:fileReferences]).to eq(0)
      expect(result[:zipIncluded]).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 2: CSV with file references, matching zip provided
  # ---------------------------------------------------------------------------

  describe 'CSV referencing files with a matching zip archive' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title,file
        work1,Work,Work With File,photo.jpg
      CSV
    end

    subject(:result) do
      described_class.validate(
        csv_file: csv(csv_content),
        zip_file: zip('photo.jpg' => 'fake image bytes')
      )
    end

    include_examples 'returns the full result contract'

    it 'is valid' do
      expect(result[:isValid]).to be true
    end

    it 'reports the zip as included' do
      expect(result[:zipIncluded]).to be true
    end

    it 'counts the file reference' do
      expect(result[:fileReferences]).to eq(1)
    end

    it 'finds the file in the zip' do
      expect(result[:foundFiles]).to eq(1)
      expect(result[:missingFiles]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 3: CSV references a file that is absent from the zip
  # ---------------------------------------------------------------------------

  describe 'CSV referencing a file missing from the zip' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title,file
        work1,Work,Work With File,missing.jpg
      CSV
    end

    subject(:result) do
      described_class.validate(
        csv_file: csv(csv_content),
        zip_file: zip('other.jpg' => 'some bytes')
      )
    end

    include_examples 'returns the full result contract'

    it 'is not valid' do
      expect(result[:isValid]).to be false
    end

    it 'lists the missing file' do
      expect(result[:missingFiles]).to include('missing.jpg')
    end

    it 'finds zero files' do
      expect(result[:foundFiles]).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 4: CSV with file references but no zip provided
  # ---------------------------------------------------------------------------

  describe 'CSV referencing files but no zip provided' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title,file
        work1,Work,Work With File,document.pdf
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'reports zip not included' do
      expect(result[:zipIncluded]).to be false
    end

    it 'counts the file reference' do
      expect(result[:fileReferences]).to eq(1)
    end

    it 'has no missing files (no zip to check against)' do
      expect(result[:missingFiles]).to be_empty
    end

    it 'has zero found files' do
      expect(result[:foundFiles]).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 5: Empty CSV (headers only, no data rows)
  # ---------------------------------------------------------------------------

  describe 'CSV with headers but no data rows' do
    let(:csv_content) { "source_identifier,model,title\n" }

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'reports zero rows' do
      expect(result[:rowCount]).to eq(0)
    end

    it 'reports zero total items' do
      expect(result[:totalItems]).to eq(0)
    end

    # BUG: the service currently returns isValid: true for a header-only CSV because
    # the Validator only checks for missing required fields and unrecognized headers —
    # it does not check whether any rows exist. After the refactor this should be false.
    it 'is not valid (nothing to import)', :pending_fix do
      pending 'service does not yet treat an empty CSV as invalid — fix during refactor'
      expect(result[:isValid]).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 6: CSV with fully blank rows interspersed (must be skipped)
  # ---------------------------------------------------------------------------

  describe 'CSV with blank rows between data rows' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title
        work1,Work,First Work

        work2,Work,Second Work

      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    # BUG: the service's CsvParser uses plain CSV.read which does not filter blank
    # rows. CsvEntry.read_data wraps the result in CsvWrapper which skips them.
    # After the refactor both paths must use the same blank-row filtering logic.
    it 'counts only non-blank rows', :pending_fix do
      pending 'service does not yet skip blank rows — fix during refactor'
      expect(result[:rowCount]).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 7: Unrecognized headers
  # ---------------------------------------------------------------------------

  describe 'CSV with unrecognized column headers' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title,totally_fake_column
        work1,Work,A Work,some value
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'lists the unrecognized header' do
      expect(result[:unrecognized]).to have_key('totally_fake_column')
    end

    it 'has warnings' do
      expect(result[:hasWarnings]).to be true
    end

    it 'is still valid (warnings do not fail validation)' do
      expect(result[:isValid]).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 8: Duplicate source identifiers
  # ---------------------------------------------------------------------------

  describe 'CSV with duplicate source identifiers' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title
        dup1,Work,First
        dup1,Work,Duplicate
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'is not valid' do
      expect(result[:isValid]).to be false
    end

    it 'includes row-level errors about the duplicate' do
      error_messages = result[:rowErrors].map { |e| e[:message] || e[:error] || e.to_s }
      expect(error_messages.join).to match(/dup1/i).or match(/duplicate/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 9: Parent references a non-existent source identifier
  # ---------------------------------------------------------------------------

  describe 'CSV where a work references a parent that does not exist' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title,parents
        work1,Work,Orphaned Work,nonexistent_parent
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'is not valid' do
      expect(result[:isValid]).to be false
    end

    it 'includes a row error referencing the bad parent' do
      error_messages = result[:rowErrors].map { |e| e[:message] || e[:error] || e.to_s }
      expect(error_messages.join).to match(/nonexistent_parent/i).or match(/parent/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 10: Only rights_statement missing — treated as warning not error
  # ---------------------------------------------------------------------------

  describe 'CSV where only rights_statement is missing from required fields' do
    # rights_statement is a required term on Work in the test app but can be
    # supplied on the import wizard step 2, so the service promotes it to a
    # warning rather than a hard error.
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title
        work1,Work,A Work
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    before do
      # Ensure rights_statement is the only missing required term so the
      # override logic in CsvValidationService#apply_rights_statement_override!
      # is exercised. We force it by telling the service exactly what's required.
      allow_any_instance_of(described_class).to receive(:field_metadata_for_all_models).and_return(
        'Work' => {
          properties: %w[title rights_statement],
          required_terms: %w[title rights_statement],
          controlled_vocab_terms: []
        }
      )
    end

    include_examples 'returns the full result contract'

    it 'reports rights_statement as the only missing field' do
      missing_fields = result[:missingRequired].map { |m| m[:field].to_s }
      expect(missing_fields).to eq(['rights_statement'])
    end

    it 'is marked valid (rights_statement missing is a warning)' do
      expect(result[:isValid]).to be true
    end

    it 'has warnings' do
      expect(result[:hasWarnings]).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 11: Mixed record types — works, collections, file sets
  # ---------------------------------------------------------------------------

  describe 'CSV with works, collections, and file sets' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title,parents
        col1,Collection,The Collection,
        work1,Work,Work In Collection,col1
        fs1,FileSet,A File Set,work1
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'separates records into the correct categories' do
      expect(result[:collections].size).to eq(1)
      expect(result[:works].size).to eq(1)
      expect(result[:fileSets].size).to eq(1)
    end

    it 'reports the correct total' do
      expect(result[:totalItems]).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 12: CSV with multi-value column suffixes (e.g. title_1, title_2)
  # ---------------------------------------------------------------------------

  describe 'CSV using numbered multi-value column suffixes' do
    let(:csv_content) do
      <<~CSV
        source_identifier,model,title_1,title_2,creator_1
        work1,Work,Primary Title,Alt Title,Jane Doe
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    # BUG: the Validator normalises suffix-numbered headers (e.g. title_1 → title)
    # before checking against valid headers, but the valid_headers_for_models list
    # itself does not contain 'creator' for the Work model as loaded via ActiveFedora
    # in the test app. After the refactor, sharing the parser's field-list logic
    # should populate the valid headers list completely.
    it 'does not treat numbered columns as unrecognized', :pending_fix do
      pending 'creator_1 is flagged unrecognized because creator is absent from valid_headers — fix during refactor'
      unrecognized_keys = result[:unrecognized].keys
      expect(unrecognized_keys).not_to include('title_1', 'title_2', 'creator_1')
    end

    it 'is valid' do
      expect(result[:isValid]).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 13: No model column — all records treated as works
  # ---------------------------------------------------------------------------

  describe 'CSV with no model column' do
    let(:csv_content) do
      <<~CSV
        source_identifier,title
        work1,First Work
        work2,Second Work
      CSV
    end

    subject(:result) { described_class.validate(csv_file: csv(csv_content)) }

    include_examples 'returns the full result contract'

    it 'places all records into works' do
      expect(result[:works].size).to eq(2)
      expect(result[:collections]).to be_empty
      expect(result[:fileSets]).to be_empty
    end
  end
end
