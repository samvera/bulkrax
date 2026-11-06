# frozen_string_literal: true

module Bulkrax
  module FileSetEntryBehavior
    class FileNameError < StandardError
    end

    class OrphanFileSetError < StandardError
    end

    class FilePathError < StandardError
    end

    extend ActiveSupport::Concern

    included do
      self.default_work_type = Bulkrax.file_model_class.to_s
    end

    def file_reference
      return 'file' if parsed_metadata&.[]('file')&.map(&:present?)&.any?
      return 'remote_files' if parsed_metadata&.[]('remote_files')&.map(&:present?)&.any?
    end

    def add_path_to_file
      return unless file_reference == 'file'

      parsed_metadata['file'].each_with_index do |filename, i|
        next if filename.blank?

        path_to_file = parser.path_to_files(filename: filename)

        parsed_metadata['file'][i] = path_to_file if path_to_file.present?
      end
      parsed_metadata['file'].delete('')

      raise FilePathError, "one or more file paths are invalid: #{parsed_metadata['file'].join(', ')}" unless parsed_metadata['file'].map { |file_path| ::File.file?(file_path) }.all?

      parsed_metadata['file']
    end

    def validate_presence_of_filename!
      return if parsed_metadata&.[](file_reference)&.map(&:present?)&.any?

      raise FileNameError, 'File set must have a filename'
    end

    def validate_presence_of_parent!
      return if parsed_metadata[related_parents_parsed_mapping]&.map(&:present?)&.any?

      raise OrphanFileSetError, 'File set must be related to at least one work'
    end

    # ObjectFactory#create_file_set attaches the file set to its parent. ValkyrieObjectFactory
    # leaves that to CreateRelationshipsJob, and only for the first parent, the one it reads.
    def parent_jobs
      return false unless valkyrie_object_factory?

      parent_identifier = Array(parsed_metadata[related_parents_parsed_mapping]).first
      # try: ImportBehavior#deleted_identifier? arrives with samvera/bulkrax#1279
      return if parent_identifier.blank? || try(:deleted_identifier?, parent_identifier)

      inherit = inherits_parent_visibility?
      # The latest row decides for relationships an earlier run left waiting
      PendingRelationship.where(child_id: identifier).update_all(inherit_parent_visibility: inherit) # rubocop:disable Rails/SkipsModelValidations
      PendingRelationship.create!(child_id: identifier, parent_id: parent_identifier, importer_run_id: importerexporter.last_run.id, order: id,
                                  inherit_parent_visibility: inherit)
    end

    # An attached file set takes its work's visibility in ValkyrieObjectFactory#update_file_set instead.
    # A new file set takes no embargo or lease dates from its row, so those visibilities follow the work's.
    def inherits_parent_visibility?
      return false if @item && Hyrax.query_service.find_parents(resource: @item).any?

      parsed_metadata['visibility'].blank? || %w[embargo lease].include?(parsed_metadata['visibility'])
    end

    # ValkyrieObjectFactory gives a file set without a visibility its parent's
    def add_visibility
      return super unless valkyrie_object_factory?

      parsed_metadata.delete('visibility') if parsed_metadata['visibility'].blank?
    end

    def child_jobs
      raise ::StandardError, "A #{Bulkrax.file_model_class} cannot be a parent of a #{Bulkrax.collection_model_class}, Work, or other #{Bulkrax.file_model_class}"
    end

    private

    def valkyrie_object_factory?
      Bulkrax.object_factory <= ValkyrieObjectFactory
    end
  end
end
