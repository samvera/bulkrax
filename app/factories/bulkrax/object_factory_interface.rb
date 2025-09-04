# frozen_string_literal: true

module Bulkrax
  ##
  # @abstract
  #
  # The purpose of the object factory is to provide an interface for interacting
  # with the underlying data repository's storage.  Each application that mounts
  # Bulkrax should configure the appropriate object factory (via
  # `Bulkrax.object_factory=`).
  #
  # The class methods are for issueing query/commands to the underlying
  # repository.
  #
  # The instance methods are for mapping a {Bulkrax::Entry} to a corresponding
  # data repository object (e.g. a Fedora Commons record or a Postgresql record
  # via ActiveFedora::Base and/or Valkyrie).
  #
  # rubocop:disable Metrics/ClassLength
  class ObjectFactoryInterface
    extend ActiveModel::Callbacks
    include DynamicRecordLookup
    include Loggable

    # We're inheriting from an ActiveRecord exception as that is something we
    # know will be here; and something that the main_app will be expect to be
    # able to handle.
    class ObjectNotFoundError < ActiveRecord::RecordNotFound
    end

    # We're inheriting from an ActiveRecord exception as that is something
    # we know will be here; and something that the main_app will be expect to be
    # able to handle.
    class RecordInvalid < ActiveRecord::RecordInvalid
    end

    ##
    # @note This does not save either object.  We need to do that in another
    #       loop.  Why?  Because we might be adding many items to the parent.
    def self.add_child_to_parent_work(parent:, child:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    def self.add_resource_to_collection(collection:, resource:, user:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # Add the user to the collection; assuming the given collection is a
    # Collection.  This is also only something we use in Hyrax.
    #
    # @param collection [#id]
    # @param user [User]
    # @see Bulkrax.collection_model_class
    def self.add_user_to_collection_permissions(collection:, user:)
      return unless collection.is_a?(Bulkrax.collection_model_class)
      return unless defined?(Hyrax)

      permission_template = Hyrax::PermissionTemplate.find_or_create_by!(source_id: collection.id)

      # NOTE: Should we extract the specific logic here?  Also, does it make
      # sense to apply permissions to the permission template (and then update)
      # instead of applying permissions directly to the collection?
      Hyrax::PermissionTemplateAccess.find_or_create_by!(
        permission_template_id: permission_template.id,
        agent_id: user.user_key,
        agent_type: 'user',
        access: 'manage'
      )

      # NOTE: This is a bit surprising that we'd add admin as a group.
      Hyrax::PermissionTemplateAccess.find_or_create_by!(
        permission_template_id: permission_template.id,
        agent_id: 'admin',
        agent_type: 'group',
        access: 'manage'
      )

      if permission_template.respond_to?(:reset_access_controls_for)
        # Hyrax 4+
        # must pass interpret_visibility: true to avoid clobbering provided visibility
        permission_template.reset_access_controls_for(collection: collection, interpret_visibility: true)
      elsif collection.respond_to?(:reset_access_controls!)
        # Hyrax 3 or earlier
        collection.reset_access_controls!
      else
        raise "Unable to reset access controls for #{collection.class} ID=#{collection.id}"
      end
    end

    ##
    # @yield when Rails application is running in test environment.
    def self.clean!
      return true unless Rails.env.test?
      yield
    end

    ##
    # @return [String]
    def self.default_admin_set_id
      if defined?(Hyrax::AdminSetCreateService::DEFAULT_ID)
        return Hyrax::AdminSetCreateService::DEFAULT_ID
      elsif defined?(AdminSet::DEFAULT_ID)
        return AdminSet::DEFAULT_ID
      else
        return 'admin_set/default'
      end
    end

    ##
    # @return [Object] when we have an existing admin set.
    # @return [NilClass] when we the default admin set does not exist.
    #
    # @see .find_or_nil
    def self.default_admin_set_or_nil
      find_or_nil(default_admin_set_id)
    end

    ##
    # @return [Array<String>]
    def self.export_properties
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # @param field [String]
    # @param model [Class]
    #
    # @return [TrueClass] when the given :field is a valid property on the given
    #         :model.

    # @return [FalseClass] when the given :field is **not** a valid property on
    #         the given :model.
    def self.field_supported?(field:, model:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # @param field [String]
    # @param model [Class]
    #
    # @return [TrueClass] when the given :field is a multi-value property on the
    #         given :model.
    # @return [FalseClass] when given :field is **not** a scalar (not
    #         multi-value) property on the given :model.
    def self.field_multi_value?(field:, model:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    def self.find_or_create_default_admin_set
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # @param resource [Object]
    #
    # @return [Array<Object>] interrogate the given :object and return an array
    #         of object's file sets.  When the object is a file set, return that
    #         file set as an Array of one element.
    def self.file_sets_for(resource:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # @see ActiveFedora::Base.find
    def self.find(id)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    def self.find_or_nil(id)
      find(id)
    rescue NotImplementedError => e
      raise e
    rescue
      nil
    end

    def self.publish(event:, **kwargs)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    def self.query(q, **kwargs)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    def self.save!(resource:, user:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    # rubocop:disable Metrics/ParameterLists
    def self.search_by_property(value:, klass:, field: nil, search_field: nil, name_field: nil, verify_property: false)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    def self.solr_name(field_name)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # @param resources [Array<Object>]
    def self.update_index(resources: [])
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # @param resource [Object] something that *might* have file_sets members.
    def self.update_index_for_file_sets_of(resource:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end
    # rubocop:enable Metrics/ParameterLists

    ##
    # @return [String] the name of the model class for the given resource/object.
    def self.model_name(resource:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end

    ##
    # @return [String] the name of the model class for the given resource/object.
    def self.thumbnail_for(resource:)
      raise NotImplementedError, "#{self}.#{__method__}"
    end
    ##
    # @api private
    #
    # These are the attributes that we assume all "work type" classes (e.g. the
    # given :klass) will have in addition to their specific attributes.
    #
    # @return [Array<Symbol>]
    # @see #permitted_attributes
    class_attribute :base_permitted_attributes,
                    default: %i[
                      admin_set_id
                      edit_groups
                      edit_users
                      id
                      read_groups
                      visibility
                      visibility_during_embargo
                      embargo_release_date
                      visibility_after_embargo
                      visibility_during_lease
                      lease_expiration_date
                      visibility_after_lease
                      work_members_attributes
                    ]

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
    attr_reader(
      :attributes,
      :importer_run_id,
      :klass,
      :object,
      :related_parents_parsed_mapping,
      :replace_files,
      :source_identifier_value,
      :update_files,
      :user,
      :work_identifier,
      :work_identifier_search_field
    )

    # rubocop:disable Metrics/ParameterLists
    def initialize(attributes:, source_identifier_value:, work_identifier:, work_identifier_search_field:, related_parents_parsed_mapping: nil, replace_files: false, user: nil, klass: nil, importer_run_id: nil, update_files: false)
      @attributes = ActiveSupport::HashWithIndifferentAccess.new(attributes)
      @replace_files = replace_files
      @update_files = update_files
      @user = user || User.batch_user
      @work_identifier = work_identifier
      @work_identifier_search_field = work_identifier_search_field
      @related_parents_parsed_mapping = related_parents_parsed_mapping
      @source_identifier_value = source_identifier_value
      @klass = klass || Bulkrax.default_work_type.constantize
      @importer_run_id = importer_run_id
    end
    # rubocop:enable Metrics/ParameterLists

    ##
    # NOTE: There has been a long-standing implementation where we might reset
    # the @update_files when we call #file_attributes.  As we refactor
    # towards extracting a class, this attr_writer preserves the behavior.
    #
    # Jeremy here, I think the behavior of setting the instance variable when
    # calling file_attributes is wrong, but now is not the time to untwine.
    attr_writer :update_files

    alias update_files? update_files

    # An ActiveFedora bug when there are many habtm <-> has_many associations
    # means they won't all get saved.
    # https://github.com/projecthydra/active_fedora/issues/874 9+ years later,
    # still open!
    def create
      attrs = transform_attributes
      @object = klass.new
      conditionally_set_reindex_extent
      run_callbacks :save do
        run_callbacks :create do
          if klass == Bulkrax.collection_model_class
            create_collection(attrs)
          elsif klass == Bulkrax.file_model_class
            create_file_set(attrs)
          else
            create_work(attrs)
          end
        end
      end

      apply_depositor_metadata
      log_created(object)
    end

    def delete(_user)
      raise NotImplementedError, "#{self.class}##{__method__}"
    end

    ##
    # @api public
    #
    # @return [Object] when we've found the object by the entry's :id or by it's
    #         source_identifier
    # @return [NilClass] when we cannot find the object.
    def find
      find_by_id || search_by_identifier || nil
    end

    ##
    # @abstract
    #
    # @return [Object] when we've found the object by the entry's :id or by it's
    #         source_identifier
    # @return [FalseClass] when we cannot find the object.
    def find_by_id
      raise NotImplementedError, "#{self.class}##{__method__}"
    end

    ##
    # @return [Object] either the one found in persistence or the one created
    #         via the run method.
    # @see .save!
    def find_or_create
      # Do we need to call save!   This was how we previously did this but it
      # seems odd that we'd not find it.  Also, why not simply call create.
      find || self.class.save!(object: run, user: @user)
    end

    def run
      arg_hash = { id: attributes[:id], name: 'UPDATE', klass: klass }

      @object = find
      if object
        conditionally_set_reindex_extent
        ActiveSupport::Notifications.instrument('import.importer', arg_hash) { update }
      else
        ActiveSupport::Notifications.instrument('import.importer', arg_hash.merge(name: 'CREATE')) { create }
      end
      yield(object) if block_given?
      object
    end

    def run!
      self.run
      # Create the error exception if the object is not validly saved for some
      # reason
      raise ObjectFactoryInterface::RecordInvalid, object if !object.persisted? || object.changed?
      object
    end

    ##
    # @return [FalseClass] when :source_identifier_value is blank or is not
    #         found via {.search_by_property} query.
    # @return [Object] when we have a source_identifier_value value and we can
    #         find it in the data store.
    def search_by_identifier
      return false if source_identifier_value.blank?

      self.class.search_by_property(
        klass: klass,
        search_field: work_identifier_search_field,
        value: source_identifier_value,
        name_field: work_identifier
      )
    end

    def update
      raise "Object doesn't exist" unless object
      conditionally_destroy_existing_files

      attrs = transform_attributes(update: true)
      run_callbacks :save do
        if klass == Bulkrax.collection_model_class
          update_collection(attrs)
        elsif klass == Bulkrax.file_model_class
          update_file_set(attrs)
        else
          update_work(attrs)
        end
      end
      apply_depositor_metadata
      log_updated(object)
    end

    def add_user_to_collection_permissions(*args)
      arguments = args.first
      self.class.add_user_to_collection_permissions(**arguments)
    end

    private

    def apply_depositor_metadata
      object.apply_depositor_metadata(@user) && object.save! if object.depositor.nil?
    end

    def clean_attrs(attrs)
      # avoid the "ArgumentError: Identifier must be a string of size > 0 in
      # order to be treeified" error when setting object.attributes
      attrs.delete('id') if attrs['id'].blank?
      attrs
    end

    def collection_type(attrs)
      return attrs if attrs['collection_type_gid'].present?

      attrs['collection_type_gid'] = Hyrax::CollectionType.find_or_create_default_collection_type.to_global_id.to_s
      attrs
    end

    def conditionally_set_reindex_extent
      return unless defined?(Hyrax::Adapters::NestingIndexAdapter)
      return unless object.respond_to?(:reindex_extent)
      object.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX
    end

    def conditionally_destroy_existing_files
      return unless @replace_files

      return if [Bulkrax.collection_model_class, Bulkrax.file_model_class].include?(klass)

      destroy_existing_files
    end

    # Regardless of what the Parser gives us, these are the properties we are
    # prepared to accept.
    def permitted_attributes
      klass.properties.keys.map(&:to_sym) + base_permitted_attributes
    end

    # Return a copy of the given attributes, such that all values that are empty
    # or an array of all empty values are fully emptied.  (See implementation
    # details)
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

    # Override if we need to map the attributes from the parser in
    # a way that is compatible with how the factory needs them.
    def transform_attributes(update: false)
      @transform_attributes = attributes.slice(*permitted_attributes)
      @transform_attributes.merge!(file_attributes(update_files?)) if with_files
      @transform_attributes = remove_blank_hash_values(@transform_attributes) if transformation_removes_blank_hash_values?
      update ? @transform_attributes.except(:id) : @transform_attributes
    end

    # update files is set, replace files is set or this is a create
    def with_files
      update_files || replace_files || !object
    end
  end
  # rubocop:enable Metrics/ClassLength
end
