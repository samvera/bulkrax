# frozen_string_literal: true

module Bulkrax
  class ObjectFactory # rubocop:disable Metrics/ClassLength
    extend ActiveModel::Callbacks
    include Bulkrax::FileFactory
    include DynamicRecordLookup

    # @api private
    #
    # These are the attributes that we assume all "work type" classes (e.g. the given :klass) will
    # have in addition to their specific attributes.
    #
    # @return [Array<Symbol>]
    # @see #permitted_attributes
    class_attribute :base_permitted_attributes,
      default: %i[id edit_users edit_groups read_groups visibility work_members_attributes admin_set_id]

    # @return [Boolean]
    #
    # @example
    #   Bulkrax::ObjectFactory.transformation_removes_blank_hash_values = true
    #
    # @see #transform_attributes
    # @see https://github.com/samvera-labs/bulkrax/pull/708 For discussion concerning this feature
    # @see https://github.com/samvera-labs/bulkrax/wiki/Interacting-with-Metadata For documentation
    #      concerning default behavior.
    class_attribute :transformation_removes_blank_hash_values, default: false

    define_model_callbacks :save, :create
    attr_reader :attributes, :object, :source_identifier_value, :klass, :replace_files, :update_files, :work_identifier, :related_parents_parsed_mapping, :importer_run_id

    # rubocop:disable Metrics/ParameterLists
    def initialize(attributes:, source_identifier_value:, work_identifier:, related_parents_parsed_mapping: nil, replace_files: false, user: nil, klass: nil, importer_run_id: nil, update_files: false)
      @attributes = ActiveSupport::HashWithIndifferentAccess.new(attributes)
      @replace_files = replace_files
      @update_files = update_files
      @user = user || User.batch_user
      @work_identifier = work_identifier
      @related_parents_parsed_mapping = related_parents_parsed_mapping
      @source_identifier_value = source_identifier_value
      @klass = klass || Bulkrax.default_work_type.constantize
      @importer_run_id = importer_run_id
    end
    # rubocop:enable Metrics/ParameterLists

    # update files is set, replace files is set or this is a create
    def with_files
      update_files || replace_files || !object
    end

    def run
      arg_hash = { id: attributes[:id], name: 'UPDATE', klass: klass }
      @object = find
      if object
        object.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX if object.respond_to?(:reindex_extent)
        ActiveSupport::Notifications.instrument('import.importer', arg_hash) { update }
      else
        ActiveSupport::Notifications.instrument('import.importer', arg_hash.merge(name: 'CREATE')) { create }
      end
      yield(object) if block_given?
      object
    end

    def run!
      self.run
      # Create the error exception if the object is not validly saved for some reason
      raise ActiveFedora::RecordInvalid, object if !object.persisted? || object.changed?
      object
    end

    def update
      raise "Object doesn't exist" unless object
      destroy_existing_files if @replace_files && ![Collection, FileSet].include?(klass)
      attrs = transform_attributes(update: true)
      run_callbacks :save do
        if klass == Collection
          update_collection(attrs)
        elsif klass == FileSet
          update_file_set(attrs)
        else
          update_work(attrs)
        end
      end
      object.apply_depositor_metadata(@user) && object.save! if object.depositor.nil?
      log_updated(object)
    end

    def find
      found = find_by_id if attributes[:id].present?
      return found if found.present?
      return search_by_identifier if attributes[work_identifier].present?
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
      # TODO(alishaevn): return the proper `work_index` value below
      # ref: https://github.com/samvera-labs/bulkrax/issues/866
      # ref:https://github.com/samvera-labs/bulkrax/issues/867
      # work_index = ::ActiveFedora.index_field_mapper.solr_name(work_identifier, :facetable)
      work_index = work_identifier
      query = { work_index =>
                source_identifier_value }
      # Query can return partial matches (something6 matches both something6 and something68)
      # so we need to weed out any that are not the correct full match. But other items might be
      # in the multivalued field, so we have to go through them one at a time.
      match = klass.where(query).detect { |m| m.send(work_identifier).include?(source_identifier_value) }
      return match if match
    end

    # An ActiveFedora bug when there are many habtm <-> has_many associations means they won't all get saved.
    # https://github.com/projecthydra/active_fedora/issues/874
    # 2+ years later, still open!
    def create
      attrs = transform_attributes
      @object = klass.new
      object.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX if object.respond_to?(:reindex_extent)
      run_callbacks :save do
        run_callbacks :create do
          if klass == Collection
            create_collection(attrs)
          elsif klass == FileSet
            create_file_set(attrs)
          else
            create_work(attrs)
          end
        end
      end
      object.apply_depositor_metadata(@user) && object.save! if object.depositor.nil?
      log_created(object)
    end

    def log_created(obj)
      msg = "Created #{klass.model_name.human} #{obj.id}"
      Rails.logger.info("#{msg} (#{Array(attributes[work_identifier]).first})")
    end

    def log_updated(obj)
      msg = "Updated #{klass.model_name.human} #{obj.id}"
      Rails.logger.info("#{msg} (#{Array(attributes[work_identifier]).first})")
    end

    def log_deleted_fs(obj)
      msg = "Deleted All Files from #{obj.id}"
      Rails.logger.info("#{msg} (#{Array(attributes[work_identifier]).first})")
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

    def create_work(attrs)
      work_actor.create(environment(attrs))
    end

    def update_work(attrs)
      work_actor.update(environment(attrs))
    end

    def create_collection(attrs)
      attrs = clean_attrs(attrs)
      attrs = collection_type(attrs)
      object.attributes = attrs
      object.save!
    end

    def update_collection(attrs)
      object.attributes = attrs
      object.save!
    end

    # This method is heavily inspired by Hyrax's AttachFilesToWorkJob
    def create_file_set(attrs)
      _, work = find_record(attributes[related_parents_parsed_mapping].first, importer_run_id)
      work_permissions = work.permissions.map(&:to_hash)
      attrs = clean_attrs(attrs)
      file_set_attrs = attrs.slice(*object.attributes.keys)
      object.assign_attributes(file_set_attrs)

      attrs['uploaded_files']&.each do |uploaded_file_id|
        uploaded_file = ::Hyrax::UploadedFile.find(uploaded_file_id)
        next if uploaded_file.file_set_uri.present?

        create_file_set_actor(attrs, work, work_permissions, uploaded_file)
      end
      attrs['remote_files']&.each do |remote_file|
        create_file_set_actor(attrs, work, work_permissions, nil, remote_file)
      end

      object.save!
    end

    def create_file_set_actor(attrs, work, work_permissions, uploaded_file, remote_file = nil)
      actor = ::Hyrax::Actors::FileSetActor.new(object, @user)
      uploaded_file&.update(file_set_uri: actor.file_set.uri)
      actor.file_set.permissions_attributes = work_permissions
      actor.create_metadata(attrs)
      actor.create_content(uploaded_file) if uploaded_file
      actor.attach_to_work(work, attrs)
      handle_remote_file(remote_file: remote_file, actor: actor, update: false) if remote_file
    end

    def update_file_set(attrs)
      file_set_attrs = attrs.slice(*object.attributes.keys)
      actor = ::Hyrax::Actors::FileSetActor.new(object, @user)
      attrs['remote_files']&.each do |remote_file|
        handle_remote_file(remote_file: remote_file, actor: actor, update: true)
      end
      actor.update_metadata(file_set_attrs)
    end

    def handle_remote_file(remote_file:, actor:, update: false)
      actor.file_set.label = remote_file['file_name']
      actor.file_set.import_url = remote_file['url']

      url = remote_file['url']
      tmp_file = Tempfile.new(remote_file['file_name'].split('.').first)
      tmp_file.binmode

      URI.open(url) do |url_file|
        tmp_file.write(url_file.read)
      end

      tmp_file.rewind
      update == true ? actor.update_content(tmp_file) : actor.create_content(tmp_file, from_url: true)
      tmp_file.close
    end

    def clean_attrs(attrs)
      # avoid the "ArgumentError: Identifier must be a string of size > 0 in order to be treeified" error
      # when setting object.attributes
      attrs.delete('id') if attrs['id'].blank?
      attrs
    end

    def collection_type(attrs)
      return attrs if attrs['collection_type_gid'].present?

      attrs['collection_type_gid'] = Hyrax::CollectionType.find_or_create_default_collection_type.gid
      attrs
    end

    # Override if we need to map the attributes from the parser in
    # a way that is compatible with how the factory needs them.
    def transform_attributes(update: false)
      @transform_attributes = attributes.slice(*permitted_attributes)
      @transform_attributes.merge!(file_attributes(update_files)) if with_files
      @transform_attributes = remove_blank_hash_values(@transform_attributes) if transformation_removes_blank_hash_values?
      update ? @transform_attributes.except(:id) : @transform_attributes
    end

    # Regardless of what the Parser gives us, these are the properties we are prepared to accept.
    def permitted_attributes
      klass.properties.keys.map(&:to_sym) + base_permitted_attributes
    end

    # Return a copy of the given attributes, such that all values that are empty or an array of all
    # empty values are fully emptied.  (See implementation details)
    #
    # @param attributes [Hash]
    # @return [Hash]
    #
    # @see https://github.com/emory-libraries/dlp-curate/issues/1973
    def remove_blank_hash_values(attributes)
      dupe = attributes.dup
      dupe.each do |key, values|
        if values.is_a?(Array) && values.all? { |value| value.is_a?(String) && value.empty? }
          dupe[key] = []
        elsif values.is_a?(String) && values.empty?
          dupe[key] = nil
        end
      end
      dupe
    end
  end
end
