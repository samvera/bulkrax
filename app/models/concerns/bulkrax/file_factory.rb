# frozen_string_literal: true

module Bulkrax
  ##
  # NOTE: Historically (e.g. Bulkrax v7.0.0 and earlier) we mixed in all of the
  # {Bulkrax::FileFactory} methods into {Bulkrax::ObjectFactory}.  However, with
  # the introduction of {Bulkrax::ValkyrieObjectFactory} we needed to account
  # for branching logic.
  #
  # This refactor where we expose the bare minimum interface of file interaction
  # should help with encapsulation.
  #
  # The refactor pattern was to find FileFactory methods used by the
  # ObjectFactory and delegate those to the new {FileFactory::InnerWorkings}
  # class.  Likewise within the InnerWorkings we wanted to delegate to the given
  # object_factory the methods that the InnerWorkings need.
  #
  # Futher, by preserving the FileFactory as a mixed in module, downstream
  # implementers will hopefully experience less of an impact regarding this
  # change.
  module FileFactory
    extend ActiveSupport::Concern

    included do
      class_attribute :file_set_factory_inner_workings_class, default: Bulkrax::FileFactory::InnerWorkings

      def file_set_factory_inner_workings
        @file_set_factory_inner_workings ||= file_set_factory_inner_workings_class.new(object_factory: self)
      end

      delegate :file_attributes, :destroy_existing_files, to: :file_set_factory_inner_workings
    end

    class InnerWorkings
      include Loggable

      def initialize(object_factory:)
        @object_factory = object_factory
      end

      attr_reader :object_factory

      delegate :object, :klass, :attributes, :user, to: :object_factory

      # Find existing files or upload new files. This assumes a Work will have unique file titles;
      #   and that those file titles will not have changed
      # could filter by URIs instead (slower).
      # When an uploaded_file already exists we do not want to pass its id in `file_attributes`
      # otherwise it gets reuploaded by `work_actor`.
      # support multiple files; ensure attributes[:file] is an Array
      def upload_ids
        return [] if klass == Bulkrax.collection_model_class
        attributes[:file] = file_paths
        import_files
      end

      def file_attributes(update_files = false)
        # NOTE: Unclear why we're changing a instance variable based on what was
        # passed, which itself is derived from the instance variable we're about
        # to change.  It's very easy to mutate the initialized @update_files if
        # you don't pass the parameter.
        object_factory.update_files = update_files
        hash = {}
        return hash if klass == Bulkrax.collection_model_class
        hash[:uploaded_files] = upload_ids if attributes[:file].present?
        hash[:remote_files] = new_remote_files if new_remote_files.present?
        hash
      end

      # Its possible to get just an array of strings here, so we need to make sure they are all hashes
      def parsed_remote_files
        return @parsed_remote_files if @parsed_remote_files.present?
        @parsed_remote_files = attributes[:remote_files] || []
        @parsed_remote_files = @parsed_remote_files.map do |file_value|
          if file_value.is_a?(Hash)
            file_value
          elsif file_value.is_a?(String)
            name = Bulkrax::Importer.safe_uri_filename(file_value)
            { url: file_value, file_name: name }
          else
            Rails.logger.error("skipped remote file #{file_value} because we do not recognize the type")
            nil
          end
        end
        @parsed_remote_files.delete(nil)
        @parsed_remote_files
      end

      def new_remote_files
        return @new_remote_files if @new_remote_files

        # TODO: This code could first loop through all remote files and select
        # only the valid ones; then load the file_sets and do comparisons.
        file_sets = object_factory.class.file_sets_for(resource: object)
        @new_remote_files = parsed_remote_files.select do |file|
          # is the url valid?
          is_valid = file[:url]&.match(URI::ABS_URI)
          # does the file already exist
          is_existing = file_sets.detect { |f| f.import_url && f.import_url == file[:url] }
          is_valid && !is_existing
        end
      end

      def file_paths
        @file_paths ||= Array.wrap(attributes[:file])&.select { |file| File.exist?(file) }
      end

      # Retrieve the orginal filenames for the files to be imported
      def work_files_filenames
        object.file_sets.map { |fn| fn.original_file.file_name.to_a }.flatten if object.present? && object.file_sets.present?
      end

      # Retrieve the filenames for the files to be imported
      def import_files_filenames
        file_paths.map { |f| f.split('/').last }
      end

      # Called if #replace_files is true
      # Destroy all file_sets for this object
      # Reload the object to ensure the remaining methods have the most up to date object
      def destroy_existing_files
        return unless object.present? && object.file_sets.present?
        object.file_sets.each do |fs|
          Hyrax::Actors::FileSetActor.new(fs, @user).destroy
        end
        @object = object.reload
        log_deleted_fs(object)
      end

      def set_removed_filesets
        local_file_sets.each do |fileset|
          # TODO: We need to consider the Valkyrie pathway
          next if fileset.is_a?(Valkyrie::Resource)

          remove_file_set(file_set: fileset)
        end
      end

      def remove_file_set(file_set:)
        # TODO: We need to consider the Valkyrie pathway
        file = file_set.files.first
        file.create_version
        opts = {}
        opts[:path] = file.id.split('/', 2).last
        opts[:original_name] = 'removed.png'
        opts[:mime_type] = 'image/png'

        file_set.add_file(File.open(Bulkrax.removed_image_path), opts)
        file_set.save
        ::CreateDerivativesJob.set(wait: 1.minute).perform_later(file_set, file.id)
      end

      def local_file_sets
        # NOTE: we'll be mutating this list of file_sets via the import_files
        # method
        @local_file_sets ||= ordered_file_sets
      end

      def ordered_file_sets
        return [] if object.blank?

        Bulkrax.object_factory.ordered_file_sets_for(object)
      end

      ##
      # @return [Array<Integer>] An array of Hyrax::UploadFile#id representing the
      #         files that we should be uploading.
      def import_files
        paths = file_paths.map { |path| import_file(path) }.compact
        set_removed_filesets if local_file_sets.present?
        paths
      end

      def import_file(path)
        u = Hyrax::UploadedFile.new
        u.user_id = user.id
        u.file = CarrierWave::SanitizedFile.new(path)
        update_filesets(u)
      end

      def update_filesets(current_file)
        if @update_files && local_file_sets.present?
          # NOTE: We're mutating local_file_sets as we process the updated file.
          fileset = local_file_sets.shift
          update_file_set(file_set: fileset, uploaded: current_file)
        else
          current_file.save
          current_file.id
        end
      end

      ##
      # @return [NilClass] indicating that we've successfully began work on the file_set.
      def update_file_set(file_set:, uploaded:)
        # TODO: We need to consider the Valkyrie pathway
        file = file_set.files.first
        uploaded_file = uploaded.file

        return nil if file.checksum.value == Digest::SHA1.file(uploaded_file.path).to_s

        file.create_version
        opts = {}
        opts[:path] = file.id.split('/', 2).last
        opts[:original_name] = uploaded_file.file.original_filename
        opts[:mime_type] = uploaded_file.content_type

        file_set.add_file(File.open(uploaded_file.to_s), opts)
        file_set.save
        ::CreateDerivativesJob.set(wait: 1.minute).perform_later(file_set, file.id)
        nil
      end
    end
  end
end
