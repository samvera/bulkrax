# frozen_string_literal: true

# TODO: require 'importer/log_subscriber'
module Bulkrax
  class ObjectFactory
    extend ActiveModel::Callbacks
    define_model_callbacks :save, :create
    class_attribute :system_identifier_field
    attr_reader :attributes, :object, :unique_identifier, :klass, :replace_files
    self.system_identifier_field = Bulkrax.system_identifier_field

    def initialize(attributes, unique_identifier, replace_files = false, user = nil, klass = nil)
      @attributes = ActiveSupport::HashWithIndifferentAccess.new(attributes)
      @replace_files = replace_files
      @user = user || User.batch_user
      @unique_identifier = unique_identifier
      @klass = klass || Bulkrax.default_work_type.constantize
    end

    def run
      arg_hash = { id: attributes[:id], name: 'UPDATE', klass: klass }
      @object = find
      if object
        object.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX
        ActiveSupport::Notifications.instrument('import.importer', arg_hash) { update }
      else
        ActiveSupport::Notifications.instrument('import.importer', arg_hash.merge(name: 'CREATE')) { create }
      end
      yield(object) if block_given?
      object
    end

    def update
      raise "Object doesn't exist" unless object
      destroy_existing_files if @replace_files && klass != Collection
      attrs = update_attributes
      run_callbacks :save do
        klass == Collection ? update_collection(attrs) : work_actor.update(environment(attrs))
      end
      log_updated(object)
    end

    def find
      return find_by_id if attributes[:id]
      return search_by_identifier if attributes[system_identifier_field].present?
    end

    def find_by_id
      klass.find(attributes[:id]) if klass.exists?(attributes[:id])
    end

    def find_or_create
      o = find
      return o if o
      run(&:save!)
    end

    def search_by_identifier
      query = { system_identifier_field =>
                unique_identifier }
      # Query can return partial matches (something6 matches both something6 and something68)
      # so we need to weed out any that are not the correct full match. But other items might be
      # in the multivalued field, so we have to go through them one at a time.
      match = klass.where(query).detect { |m| m.send(system_identifier_field).include?(unique_identifier) }
      return match if match
    end

    # An ActiveFedora bug when there are many habtm <-> has_many associations means they won't all get saved.
    # https://github.com/projecthydra/active_fedora/issues/874
    # 2+ years later, still open!
    def create
      attrs = create_attributes
      @object = klass.new
      object.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX
      run_callbacks :save do
        run_callbacks :create do
          klass == Collection ? create_collection(attrs) : work_actor.create(environment(attrs))
        end
      end
      log_created(object)
    end

    def log_created(obj)
      msg = "Created #{klass.model_name.human} #{obj.id}"
      Rails.logger.info("#{msg} (#{Array(attributes[system_identifier_field]).first})")
    end

    def log_updated(obj)
      msg = "Updated #{klass.model_name.human} #{obj.id}"
      Rails.logger.info("#{msg} (#{Array(attributes[system_identifier_field]).first})")
    end

    def log_deleted_fs(obj)
      msg = "Deleted All Files from #{obj.id}"
      Rails.logger.info("#{msg} (#{Array(attributes[system_identifier_field]).first})")
    end

    private

      # @param [Hash] attrs the attributes to put in the environment
      # @return [Hyrax::Actors::Environment]
      def environment(attrs)
        Hyrax::Actors::Environment.new(object, Ability.new(@user), attrs)
      end

      def work_actor
        Hyrax::CurationConcern.actor
      end

      def create_collection(attrs)
        attrs = collection_type(attrs)
        object.members = members
        object.member_of_collections = member_of_collections
        object.attributes = attrs
        object.apply_depositor_metadata(@user)
        object.save!
      end

      def update_collection(attrs)
        object.members = members
        object.member_of_collections = member_of_collections
        object.attributes = attrs
        object.save!
      end

      # Collections don't respond to member_of_collections_attributes or member_of_collection_ids=
      #   or member_ids=
      # Add them directly with members / member_of_collections
      # collection should be in the form  { id: collection_id }
      # and collections [{ id: collection_id }]
      # member_ids comes from
      # @todo - consider performance implications although we wouldn't expect a Collection to be a member of many Collections
      def members
        ms = object.members.to_a
        [:children].each do |atat|
          next unless attributes[atat].present?
          ms.concat(
            Array.wrap(
              find_collection(attributes[atat])
            )
          )
        end
        ms.flatten.compact.uniq
      end

      def member_of_collections
        ms = object.member_of_collection_ids.to_a.map { | id | find_collection(id) }
        [:collection, :collections].each do |atat|
          next unless attributes[atat].present?
          ms.concat(
            Array.wrap(
              find_collection(attributes[atat])
            )
          )
        end
        ms.flatten.compact.uniq
      end

      def find_collection(id)
        case id
        when Hash
          Collection.find(id[:id])
        when String
          Collection.find(id)
        when Array
          id.map { |i| find_collection(i) }
        else
          []
        end
      end

      def collection_type(attrs)
        return attrs if attrs['collection_type_gid'].present?
        attrs['collection_type_gid'] = Hyrax::CollectionType.find_or_create_default_collection_type.gid
        attrs
      end

      # Strip out the :collection key, and add the member_of_collection_ids,
      # which is used by Hyrax::Actors::AddAsMemberOfCollectionsActor
      def create_attributes
        return transform_attributes if klass == Collection
        if attributes[:collection].present?
          transform_attributes.except(:collection).merge(member_of_collections_attributes: { 0 => { id: collection.id } })
        elsif attributes[:collections].present?
          collection_ids = attributes[:collections].each.with_index.each_with_object({}) do |(element, index), ids|
            ids[index] = element
          end
          transform_attributes.except(:collections).merge(member_of_collections_attributes: collection_ids)
        else
          transform_attributes
        end
      end

      # Strip out the :collection key, and add the member_of_collection_ids,
      # which is used by Hyrax::Actors::AddAsMemberOfCollectionsActor
      def update_attributes
        return transform_attributes.except(:id) if klass == Collection
        if attributes[:collection].present?
          transform_attributes.except(:id).except(:collection).merge(member_of_collections_attributes: { 0 => { id: collection.id } })
        elsif attributes[:collections].present?
          collection_ids = attributes[:collections].each.with_index.each_with_object({}) do |(element, index), ids|
            ids[index] = element
          end
          transform_attributes.except(:id).except(:collections).merge(member_of_collections_attributes: collection_ids)
        else
          transform_attributes.except(:id)
        end
      end

      # Override if we need to map the attributes from the parser in
      # a way that is compatible with how the factory needs them.
      def transform_attributes
        attributes.slice(*permitted_attributes)
                  .merge(file_attributes)
      end

      # Find existing files or upload new files. This assumes a Work will have unique file titles;
      #   and that those file titles will not have changed
      # could filter by URIs instead (slower).
      # When an uploaded_file already exists we do not want to pass its id in `file_attributes`
      # otherwise it gets reuploaded by `work_actor`.
      # support multiple files; ensure attributes[:file] is an Array
      def upload_ids
        return [] if klass == Collection
        attributes[:file] = file_paths
        work_files_filenames && (work_files_filenames & import_files_filenames).present? ? [] : import_files
      end

      def file_attributes
        hash = {}
        return hash if klass == Collection
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
            { url: file_value }
          else
            Rails.logger.error("skipped remote file #{file_value} because we do not recognize the type")
            nil
          end
        end
        @parsed_remote_files.delete(nil)
        @parsed_remote_files
      end

      def new_remote_files
        @new_remote_files ||= if object.present? && object.file_sets.present?
                                parsed_remote_files.select do |file|
                                  # is the url valid?
                                  is_valid = file[:url]&.match(URI::ABS_URI)
                                  # does the file already exist
                                  is_existing = object.file_sets.detect { |f| f.import_url && f.import_url == file[:url] }
                                  is_valid && !is_existing
                                end
                              else
                                parsed_remote_files.select do |file|
                                  file[:url]&.match(URI::ABS_URI)
                                end
                              end
      end

      def file_paths
        @file_paths ||= Array.wrap(attributes[:file])&.map { |file| file if File.exist?(file) }
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

      def import_files
        file_paths.map { |path| import_file(path) }
      end

      def import_file(path)
        u = Hyrax::UploadedFile.new
        u.user_id = @user.id
        u.file = CarrierWave::SanitizedFile.new(path)
        u.save
        u.id
      end

      # Regardless of what the Parser gives us, these are the properties we are prepared to accept.
      def permitted_attributes
        klass.properties.keys.map(&:to_sym) + %i[id edit_users edit_groups read_groups visibility work_members_attributes]
      end
  end
end
