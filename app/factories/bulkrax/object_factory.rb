# frozen_string_literal: true

module Bulkrax
  class ObjectFactory
    extend ActiveModel::Callbacks
    include Bulkrax::FileFactory
    define_model_callbacks :save, :create
    attr_reader :attributes, :object, :source_identifier_value, :klass, :replace_files, :update_files, :work_identifier

    # rubocop:disable Metrics/ParameterLists
    def initialize(attributes:, source_identifier_value:, work_identifier:, replace_files: false, user: nil, klass: nil, update_files: false)
      @attributes = ActiveSupport::HashWithIndifferentAccess.new(attributes)
      @replace_files = replace_files
      @update_files = update_files
      @user = user || User.batch_user
      @work_identifier = work_identifier
      @source_identifier_value = source_identifier_value
      @klass = klass || Bulkrax.default_work_type.constantize
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
        object.reindex_extent = Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX
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
    end

    def update
      raise "Object doesn't exist" unless object
      destroy_existing_files if @replace_files && klass != Collection
      attrs = attribute_update
      run_callbacks :save do
        klass == Collection ? update_collection(attrs) : work_actor.update(environment(attrs))
      end
      log_updated(object)
    end

    def find
      return find_by_id if attributes[:id]
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
      query = { work_identifier =>
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
        next if attributes[atat].blank?
        ms.concat(
          Array.wrap(
            find_collection(attributes[atat])
          )
        )
      end
      ms.flatten.compact.uniq
    end

    def member_of_collections
      ms = object.member_of_collection_ids.to_a.map { |id| find_collection(id) }
      [:collection, :collections].each do |atat|
        next if attributes[atat].blank?
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
          ids[index] = { id: element }
        end
        transform_attributes.except(:collections).merge(member_of_collections_attributes: collection_ids)
      else
        transform_attributes
      end
    end

    # Strip out the :collection key, and add the member_of_collection_ids,
    # which is used by Hyrax::Actors::AddAsMemberOfCollectionsActor
    def attribute_update
      return transform_attributes.except(:id) if klass == Collection
      if attributes[:collection].present?
        transform_attributes.except(:id).except(:collection).merge(member_of_collections_attributes: { "0" => { id: collection.id } })
      elsif attributes[:collections].present?
        collection_ids = attributes[:collections].each.with_index.each_with_object({}) do |(element, index), ids|
          ids[index.to_s] = element
        end
        transform_attributes.except(:id).except(:collections).merge(member_of_collections_attributes: collection_ids)
      else
        transform_attributes.except(:id)
      end
    end

    # Override if we need to map the attributes from the parser in
    # a way that is compatible with how the factory needs them.
    def transform_attributes
      @transform_attributes = attributes.slice(*permitted_attributes)
      @transform_attributes.merge!(file_attributes(update_files)) if with_files
      @transform_attributes
    end

    # Regardless of what the Parser gives us, these are the properties we are prepared to accept.
    def permitted_attributes
      klass.properties.keys.map(&:to_sym) + %i[id edit_users edit_groups read_groups visibility work_members_attributes admin_set_id]
    end
  end
end
