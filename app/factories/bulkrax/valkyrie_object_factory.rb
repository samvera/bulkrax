# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ClassLength
  class ValkyrieObjectFactory < ObjectFactoryInterface
    class FileFactoryInnerWorkings < Bulkrax::FileFactory::InnerWorkings
      # A Valkyrie file set has no import_url to compare; when its row is updated, the checksum
      # decides whether its file changed (see ValkyrieObjectFactory#replace_original_file).
      def new_remote_files
        return super unless object.is_a?(Bulkrax.file_model_class)

        @new_remote_files ||= parsed_remote_files.select { |file| file[:url]&.match(URI::ABS_URI) }
      end

      def remove_file_set(file_set:)
        file_metadata = Hyrax.custom_queries.find_files(file_set: file_set).first
        raise "No file metadata records found for #{file_set.class} ID=#{file_set.id}" unless file_metadata

        Hyrax::VersioningService.create(file_metadata, user, File.new(Bulkrax.removed_image_path))

        ::ValkyrieCreateDerivativesJob.set(wait: 1.minute).perform_later(file_set.id, file_metadata.id)
      end

      ##
      # Replace an existing :file_set's file with the :uploaded file.
      #
      # @param file_set [Hyrax::FileSet, Object]
      # @param uploaded [Hyrax::UploadedFile]
      #
      # @return [NilClass]
      def update_file_set(file_set:, uploaded:)
        file_metadata = Hyrax.custom_queries.find_files(file_set: file_set).first
        raise "No file metadata records found for #{file_set.class} ID=#{file_set.id}" unless file_metadata

        uploaded_file = uploaded.file

        # TODO: Is this accurate?  We'll need to interrogate the file_metadata
        # object.  Should it be `file_metadata.checksum.first.to_s` Or something
        # else?
        return nil if file_metadata.checksum.first == Digest::SHA1.file(uploaded_file.path).to_s

        Hyrax::VersioningService.create(file_metadata, user, uploaded_file)

        ::ValkyrieCreateDerivativesJob.set(wait: 1.minute).perform_later(file_set.id, file_metadata.id)
        nil
      end
    end

    # Customized create method for Valkyrie so that @object gets set
    def create
      attrs = transform_attributes
      @object = klass.new
      conditionally_set_reindex_extent
      run_callbacks :save do
        run_callbacks :create do
          @object = if klass == Bulkrax.collection_model_class
                      create_collection(attrs)
                    elsif klass == Bulkrax.file_model_class
                      create_file_set(attrs)
                    else
                      create_work(attrs)
                    end
        end
      end

      apply_depositor_metadata
      log_created(@object)
    end

    # Customized update method for Valkyrie so that @object gets set
    def update
      raise "Object doesn't exist" unless object
      conditionally_destroy_existing_files

      attrs = transform_attributes(update: true)
      run_callbacks :save do
        @object = if klass == Bulkrax.collection_model_class
                    update_collection(attrs)
                  elsif klass == Bulkrax.file_model_class
                    update_file_set(attrs)
                  else
                    update_work(attrs)
                  end
      end
      apply_depositor_metadata
      log_updated(@object)
    end

    # TODO: the following module needs revisiting for Valkyrie work.
    #       proposal is to create Bulkrax::ValkyrieFileFactory.
    include Bulkrax::FileFactory

    self.file_set_factory_inner_workings_class = Bulkrax::ValkyrieObjectFactory::FileFactoryInnerWorkings

    delegate :transactions, to: :class

    ##
    # When you want a different set of transactions you can change the
    # container.
    #
    # @note Within {Bulkrax::ValkyrieObjectFactory} there are several calls to
    #       transactions; so you'll need your container to register those
    #       transactions.
    def self.transactions
      @transactions || Hyrax::Transactions::Container
    end

    ##
    # @!group Class Method Interface

    ##
    # When adding a child to a parent work, we save the parent.
    # Locking appears inconsistent, so we are finding the parent and
    # saving it with each child, but waiting until the end to reindex.
    # To do this we are bypassing the save! method defined below
    def self.add_child_to_parent_work(parent:, child:)
      parent = self.find(parent.id)
      return parent if parent.member_ids.include?(child.id)
      reject_second_work(parent: parent, child: child)
      parent.member_ids += [child.id]
      if child.is_a?(Bulkrax.file_model_class)
        parent.representative_id = child.id if parent.respond_to?(:representative_id) && parent.representative_id.blank?
        parent.thumbnail_id = child.id if parent.respond_to?(:thumbnail_id) && parent.thumbnail_id.blank?
      end
      Hyrax.persister.save(resource: parent)
    end

    def self.reject_second_work(parent:, child:)
      return unless child.is_a?(Bulkrax.file_model_class)

      other = Hyrax.query_service.find_parents(resource: child).map(&:id).find { |id| id != parent.id }
      raise FileSetInAnotherWorkError, "#{child.id} is already in work #{other}; adding it to work #{parent.id} is not supported" if other
    end
    private_class_method :reject_second_work

    ##
    # File sets are created unattached (see #create_file_set), so their files are ingested once
    # CreateRelationshipsJob has attached them. A file set already a member with no files is one
    # a killed pass attached but never queued.
    def self.uploads_awaiting_ingest(resource:)
      return [] unless resource.is_a?(Bulkrax.file_model_class) && resource.file_ids.blank?

      Hyrax::UploadedFile.where(file_set_uri: resource.id.to_s).to_a
    end

    def self.ingest_later(upload:)
      # perform_later returns false, without raising, when a callback aborts the enqueue
      ::ValkyrieIngestJob.perform_later(upload) || raise("Could not queue the ingest of upload #{upload.id}")
    end

    def self.inherit_parent_visibility(parent:, resource:)
      return resource unless resource.is_a?(Bulkrax.file_model_class)
      return resource if under_embargo_or_lease?(resource)

      inherit_visibility(from: parent, to: resource)
    end

    def self.inherit_visibility(from:, to:)
      clear_ended_embargo_and_lease(to)
      to.visibility = visibility_after_ended_policy(from) || from.visibility
      Hyrax::EmbargoManager.new(resource: from).copy_embargo_to(target: to)
      Hyrax::LeaseManager.new(resource: from).copy_lease_to(target: to)
      to.permission_manager.acl.save
      Hyrax.persister.save(resource: to).tap { |saved| Hyrax.index_adapter.save(resource: saved) }
    end

    # An embargo or lease that ended keeps its during visibility until Hyrax releases it, and is not
    # copied, so the file set takes the visibility it ends in
    def self.visibility_after_ended_policy(work)
      embargo = work.embargo
      return embargo.visibility_after_embargo if embargo&.embargo_release_date.present? && !embargo.active?

      lease = work.lease
      lease.visibility_after_lease if lease&.lease_expiration_date.present? && !lease.active?
    end

    POLICY_FIELDS = { embargo: %i[embargo_release_date visibility_during_embargo visibility_after_embargo],
                      lease: %i[lease_expiration_date visibility_during_lease visibility_after_lease] }.freeze

    # An ended embargo or lease left on the file set would let Hyrax's expiry jobs later
    # release it to the visibility it was to have afterwards
    def self.clear_ended_embargo_and_lease(file_set)
      POLICY_FIELDS.each do |policy_name, fields|
        policy = file_set.public_send(policy_name)
        next if policy.nil? || policy.active?

        fields.each { |field| policy.public_send("#{field}=", nil) }
        # Hyrax 4 embeds it with no id, and saving the file set saves it
        Hyrax.persister.save(resource: policy) if policy.id.present?
      end
    end

    # Its own embargo or lease keeps a file set as it is until it ends
    def self.under_embargo_or_lease?(file_set)
      Hyrax::EmbargoManager.new(resource: file_set).under_embargo? || Hyrax::LeaseManager.new(resource: file_set).under_lease?
    end
    private_class_method :clear_ended_embargo_and_lease, :visibility_after_ended_policy

    ##
    # The resource added to a collection can be either a work or another collection.
    def self.add_resource_to_collection(collection:, resource:, user:)
      resource = self.find(resource.id)
      resource.member_of_collection_ids += [collection.id]
      save!(resource: resource, user: user)
    end

    def self.field_multi_value?(field:, model:, admin_set_id: nil)
      return false unless field_supported?(field: field, model: model, admin_set_id: admin_set_id)

      if model.respond_to?(:schema)
        schema = cached_schema_for(klass: model, admin_set_id: admin_set_id)
        dry_type = schema.key(field.to_sym)
        return true if dry_type.respond_to?(:primitive) && dry_type.primitive == Array

        false
      else
        Bulkrax::ObjectFactory.field_multi_value?(field: field, model: model)
      end
    end

    def self.field_supported?(field:, model:, admin_set_id: nil)
      if model.respond_to?(:schema)
        schema_properties(klass: model, admin_set_id: admin_set_id).include?(field)
      else
        # We *might* have a Fedora object, so we need to consider that approach as
        # well.
        Bulkrax::ObjectFactory.field_supported?(field: field, model: model)
      end
    end

    def self.file_sets_for(resource:)
      return [] if resource.blank?
      return [resource] if resource.is_a?(Bulkrax.file_model_class)

      Hyrax.query_service.custom_queries.find_child_file_sets(resource: resource)
    end

    def self.find(id)
      Hyrax.query_service.find_by(id: id)
      # Because Hyrax is not a hard dependency, we need to transform the Hyrax exception into a
      # common exception so that callers can handle a generalize exception.
    rescue Hyrax::ObjectNotFoundError, Valkyrie::Persistence::ObjectNotFoundError => e
      raise ObjectFactoryInterface::ObjectNotFoundError, e.message
    end

    # Neither lookup is limited to the row's model, so a record of another
    # model is reported rather than updated as if it were the row's.
    def self.record_of_row_model(record, klass:, identifier:)
      return record if record.nil? || record_of_model?(record, klass)

      raise ObjectFactoryInterface::ModelMismatchError.new(identifier: identifier, existing_model: record.class, model: klass)
    end

    def self.record_for_id(id, klass:) # rubocop:disable Lint/UnusedMethodArgument
      return false if id.blank?

      find(id)
    end

    def self.record_of_model?(record, klass)
      config = Bulkrax.config
      twin = config.file_model_name?(klass.to_s) ? config.file_set_twin_for(klass) : config.curation_concern_twin_for(klass)
      config.model_names_for(klass, twin: twin).include?(record.class.to_s)
    end
    private_class_method :record_of_model?

    def self.find_or_create_default_admin_set
      Hyrax::AdminSetCreateService.find_or_create_default_admin_set
    end

    def self.solr_name(field_name)
      # It's a bit unclear what this should be if we can't rely on Hyrax.
      raise NotImplementedError, "#{self}.#{__method__}" unless defined?(Hyrax)
      Hyrax.config.index_field_mapper.solr_name(field_name)
    end

    def self.publish(event:, **kwargs)
      # It's a bit unclear what this should be if we can't rely on Hyrax.
      raise NotImplementedError, "#{self}.#{__method__}" unless defined?(Hyrax)
      Hyrax.publisher.publish(event, **kwargs)
    end

    def self.query(q, **kwargs)
      # Someone could choose ActiveFedora::SolrService.  But I think we're
      # assuming Valkyrie is specifcally working for Hyrax.  Someone could make
      # another object factory.
      raise NotImplementedError, "#{self}.#{__method__}" unless defined?(Hyrax)
      Hyrax::SolrService.query(q, **kwargs)
    end

    def self.save!(resource:, user:)
      if defined?(Hyrax)
        result = Hyrax.persister.save(resource: resource)
        raise Valkyrie::Persistence::ObjectNotFoundError unless result
        Hyrax.index_adapter.save(resource: result)
        if result.collection?
          self.publish(event: 'collection.metadata.updated', collection: result, user: user)
        else
          self.publish(event: 'object.metadata.updated', object: result, user: user)
        end
      else
        resource.save!
      end
      resource
    end

    def self.update_index(resources:)
      Array(resources).each do |resource|
        Hyrax.index_adapter.save(resource: resource)
      end
    end

    def self.update_index_for_file_sets_of(resource:)
      file_sets = Hyrax.query_service.custom_queries.find_child_file_sets(resource: resource)
      update_index(resources: file_sets)
    end

    ##
    # If we always want the valkyrized resource name, even for unmigrated objects, we can
    # simply use resource.model_name.name. At this point, we are differentiating
    # to help identify items which have been migrated to Valkyrie vs those which have not.
    #
    # @return [String] the name of the model class for the given resource/object.
    def self.model_name(resource:)
      resource.class.to_s
    end

    ##
    # @return [File or FileMetadata] the thumbnail file for the given resource
    def self.thumbnail_for(resource:)
      # recursive call to parent if resource is a fileset - we want the work's thumbnail
      return thumbnail_for(resource: resource&.parent) if resource.is_a?(Bulkrax.file_model_class)

      return nil unless resource.respond_to?(:thumbnail_id) && resource.thumbnail_id.present?
      Bulkrax.object_factory.find(resource.thumbnail_id.to_s)
    rescue Bulkrax::ObjectFactoryInterface::ObjectNotFoundError
      nil
    end

    ##
    # @input [Fileset or FileMetadata]
    # @return [FileMetadata] the original file
    def self.original_file(fileset:)
      return fileset if fileset.is_a?(Hyrax::FileMetadata)
      fileset.try(:original_file)
    end

    ##
    # #input [Fileset or FileMetadata]
    # @return [String] the file name for the given fileset
    def self.filename_for(fileset:)
      file = original_file(fileset: fileset)
      return nil unless file
      file.original_filename
    rescue NoMethodError
      nil
    end

    ##
    # @param value [String]
    # @param klass [Class, #where]
    # @param field [String, Symbol] A convenience parameter where we pass the
    #        same value to search_field and name_field.
    # @param name_field [String] the ActiveFedora::Base property name
    #        (e.g. "title")
    # @return [NilClass] when no object is found.
    # @return [Valkyrie::Resource] when a match is found, an instance of given
    #         :klass
    # rubocop:disable Metrics/ParameterLists
    def self.search_by_property(value:, field: nil, name_field: nil, search_field:, **)
      name_field ||= field
      raise "Expected named_field or field got nil" if name_field.blank?
      return if value.blank?
      # Return nil or a single object.
      Hyrax.query_service.custom_queries.find_by_property_value(property: name_field, value: value, search_field: search_field)
    end
    # rubocop:enable Metrics/ParameterLists

    ##
    # Retrieve schema property names for a model, respecting admin set contexts
    # when using flexible metadata. Delegates context resolution to Hyrax so
    # Bulkrax does not need to know about HYRAX_FLEXIBLE or contexts.
    #
    # @param klass [Class] the model class
    # @param admin_set_id [String, nil] admin set used to resolve contexts
    # @return [Array<String>]
    def self.schema_properties(klass:, admin_set_id: nil)
      entry = schema_cache_entry(klass: klass, admin_set_id: admin_set_id)
      entry[:properties] ||= entry[:schema].map { |k| k.name.to_s }.freeze
    end

    ##
    # Returns the schema for a model, memoized per (tenant, klass, admin_set_id)
    # for the current request or job only, so a new metadata profile or a
    # change to an admin set's contexts is picked up without a restart.
    # Delegates to +Hyrax.schema_for+ when available so that context-gated
    # properties are included without Bulkrax knowing about flexibility internals.
    #
    # @param klass [Class]
    # @param admin_set_id [String, nil]
    # @return [Dry::Types::Hash]
    def self.cached_schema_for(klass:, admin_set_id: nil)
      schema_cache_entry(klass: klass, admin_set_id: admin_set_id)[:schema]
    end

    def self.schema_cache_entry(klass:, admin_set_id:)
      tenant = defined?(Apartment::Tenant) ? Apartment::Tenant.current : 'single'
      Bulkrax::Current.schema_cache ||= {}
      Bulkrax::Current.schema_cache[[tenant, klass, admin_set_id]] ||= { schema: resolve_schema(klass: klass, admin_set_id: admin_set_id) }
    end
    private_class_method :schema_cache_entry

    def self.resolve_schema(klass:, admin_set_id:)
      if admin_set_id.present? && defined?(Hyrax) && Hyrax.respond_to?(:schema_for)
        Hyrax.schema_for(klass: klass, admin_set_id: admin_set_id)
      else
        klass.new.singleton_class.schema || klass.schema
      end
    end
    private_class_method :resolve_schema

    def self.ordered_file_sets_for(object)
      return [] if object.blank?

      Hyrax.custom_queries.find_child_file_sets(resource: object)
    end

    def delete(user)
      obj = find
      raise ObjectFactoryInterface::ObjectNotFoundError, "Object not found to delete" unless obj
      # delete the file sets when we delete a work
      # This has to be done before the work is deleted or we can't find them
      # via the custom query
      destroy_existing_files(object: obj)

      Hyrax.persister.delete(resource: obj)
      Hyrax.index_adapter.delete(resource: obj)
      Hyrax.publisher.publish('object.deleted', object: obj, user: user)
    end

    def run!
      run
      # reload the object
      object = find
      return object if object&.persisted?

      raise(ObjectFactoryInterface::RecordInvalid, object)
    end

    private

    def apply_depositor_metadata
      return if @object.depositor.present?

      @object.depositor = @user.email
      object = Hyrax.persister.save(resource: @object)
      Hyrax.publisher.publish("object.metadata.updated", object: object, user: @user)
      object
    end

    def conditionall_apply_depositor_metadata
      # We handle this in transactions
      nil
    end

    def conditionally_set_reindex_extent
      # Valkyrie does not concern itself with the reindex extent; no nesting
      # indexers here!
      nil
    end

    # Saving the parent here would save the member_ids it was read with, dropping file sets
    # other rows added meanwhile, so the file set is left for CreateRelationshipsJob to attach.
    # It takes the parent's permissions and the row's visibility, or else stays restricted until
    # the job gives it the visibility of the work it is attached to.
    def create_file_set(attrs)
      attrs = HashWithIndifferentAccess.new(attrs)
      parent = row_parent || raise(StandardError, "#{source_identifier_value} names no parent")
      uploaded_files, = prep_fileset_content(attrs)
      raise StandardError, "#{source_identifier_value} lists #{uploaded_files.size} files; a file set row takes one" if uploaded_files.size > 1

      upload = uploaded_files.first
      raise StandardError, "#{source_identifier_value} has no file to attach" if upload.nil? || upload.file_set_uri.present?

      params = attrs.merge(attributes).symbolize_keys
      # A visibility only a work can carry, such as embargo or lease, counts as none
      params.delete(:visibility) unless Hyrax.config.visibility_map.visibilities.include?(params[:visibility])
      create_unattached_file_set(parent, upload, params)
    end

    # The row's first parent, or nil when it names none
    def row_parent
      identifier = Array(attributes[related_parents_parsed_mapping]).first
      return if identifier.blank?

      parent = find_record(identifier, importer_run_id).last
      raise StandardError, "#{source_identifier_value} names parent #{identifier}, which was not found" unless parent
      raise StandardError, "#{source_identifier_value} names parent #{identifier}, which is a #{parent.class}, not a work" unless parent.work?

      parent
    end

    # Hyrax::WorkUploadsHandler#make_file_set_and_ingest as of Hyrax 5.3, minus adding the file
    # set to the work and, as Hyrax 4 also does there, queueing its ingest
    def create_unattached_file_set(parent, upload, params)
      file_set = Hyrax.persister.save(resource: Bulkrax.file_model_class.new(file_set_attributes(upload).merge(params)))
      Hyrax.publisher.publish('object.deposited', object: file_set, user: upload.user)
      upload.add_file_set!(file_set)
      Hyrax::AccessControlList.copy_permissions(source: Hyrax::AccessControlList.new(resource: parent), target: file_set)
      file_set.visibility = params[:visibility].presence || Hydra::AccessControls::AccessRight::VISIBILITY_TEXT_VALUE_PRIVATE
      file_set.permission_manager.acl.save if file_set.permission_manager.acl.pending_changes?
      file_set
    end

    def file_set_attributes(upload)
      { depositor: upload.user.user_key,
        creator: [upload.user.user_key],
        date_uploaded: upload.created_at,
        date_modified: Hyrax::TimeService.time_in_utc,
        label: upload.uploader.filename,
        title: [upload.uploader.filename] }
    end

    def create_work(attrs)
      # NOTE: We do not add relationships here; that is part of the create relationships job.
      attrs = HashWithIndifferentAccess.new(attrs)
      perform_transaction_for(object: object, attrs: attrs) do
        uploaded_files, file_set_params = prep_fileset_content(attrs)
        transactions["change_set.create_work"]
          .with_step_args(
            'work_resource.add_file_sets' => { uploaded_files: uploaded_files, file_set_params: file_set_params },
            "change_set.set_user_as_depositor" => { user: @user },
            "work_resource.change_depositor" => { user: @user },
            'work_resource.save_acl' => { permissions_params: [attrs.try('visibility') || 'open'].compact }
          )
      end
    end

    ## Prepare fileset data in the required format for creating or updating a work
    # TODO: Determine why attrs is different from attributes?
    # TODO: Disabled s3 until we get additional details
    def prep_fileset_content(attrs)
      # combine remote_files + thumbnail_url [Array < { url:, file_name:, * }]
      thumbnail_url = HashWithIndifferentAccess.new(self.attributes)['thumbnail_url']
      all_remote_files = merge_thumbnails(remote_files: attrs["remote_files"], thumbnail_url: thumbnail_url)
      # combine local & remote files [Array < Hash &/or String]
      all_local_files = self.attributes['file'] || []
      all_files = all_local_files + all_remote_files

      # collect all uploaded files [Array < Hyrax::UploadedFile]
      uploaded_local = uploaded_local_files(uploaded_files: attrs[:uploaded_files])
      uploaded_remote = uploaded_remote_files(remote_files: all_remote_files)
      # uploaded_s3 = uploaded_s3_files(remote_files: attrs[:remote_files])
      uploaded_files = uploaded_local + uploaded_remote

      # add in other attributes
      file_set_params = file_set_params_for(uploads: uploaded_files, files: all_files)
      # return data for filesets
      [uploaded_files, file_set_params]
    end

    # supports using thumbnail_url to import a thumbnail separately from other remote_files
    # in the format thumbnail_url: { url:, file_name: }
    def merge_thumbnails(remote_files:, thumbnail_url:)
      r = remote_files || []
      thumbnail_url.present? ? r + [thumbnail_url] : r
    end

    # formats file info and facilitates additional custom file_set attributes
    # To have the additional attributes appear on the file_set, they must be:
    # - included in the file_set_metadata.yaml
    # - overridden in file_set_args from Hyrax::WorkUploadsHandler
    # @param uploads [Array < Hyrax::UploadedFile]
    # @param files [Array < Hash or String]
    # @return [Array < Hash]
    def file_set_params_for(uploads:, files:)
      # remove url, file_name and paths from attributes
      additional_attributes = files.map do |f|
        case f
        when String
          {}
        else
          temp = f.reject { |key, _| key.to_s == 'url' || key.to_s == 'file_name' }
          temp['import_url'] = f['url']
          temp
        end
      end

      file_attrs = []
      uploads.each_with_index do |f, index|
        file_attrs << { uploaded_file_id: f["id"].to_s, filename: files[index]["file_name"] }.merge(additional_attributes[index])
      end
      file_attrs.compact.uniq
    end

    def create_collection(attrs)
      # TODO: Handle Collection Type
      #
      # NOTE: We do not add relationships here; that is part of the create
      # relationships job.
      perform_transaction_for(object: object, attrs: attrs) do
        transactions['change_set.create_collection']
          .with_step_args(
            'change_set.set_user_as_depositor' => { user: @user },
            'collection_resource.apply_collection_type_permissions' => { user: @user }
          )
      end
    end

    ##
    # @param object [Valkyrie::Resource]
    # @param attrs [Valkyrie::Resource]
    # @return [Valkyrie::Resource] when we successfully processed the
    #         transaction (e.g. the transaction's data was valid according to
    #         the derived form)
    #
    # @yield the returned value of the yielded block should be a
    #        {Hyrax::Transactions::Transaction}.  We yield because the we first
    #        want to check if the attributes are valid.  And if so, then process
    #        the transaction, which is something that could trigger expensive
    #        operations.  Put another way, don't do something expensive if the
    #        data is invalid.
    #
    # TODO What do we return when the calculated form fails?
    # @raise [StandardError] when there was a failure calling the translation.
    def perform_transaction_for(object:, attrs:)
      admin_set_id = attrs[:admin_set_id] || attrs['admin_set_id'] ||
                     attributes[:admin_set_id] || attributes['admin_set_id']
      form = Hyrax::Forms::ResourceForm.for(resource: object, admin_set_id: admin_set_id).prepopulate!

      # TODO: Handle validations
      form.validate(attrs)

      transaction = yield

      result = transaction.call(form)

      result.value_or do
        msg = result.failure[0].to_s
        msg += " - #{result.failure[1].full_messages.join(',')}" if result.failure[1].respond_to?(:full_messages)
        raise StandardError, msg, result.trace
      end
    end

    ##
    # We accept attributes based on the model schema. Passes the admin set ID
    # so that context-restricted properties are included in the permitted list.
    #
    # @return [Array<Symbols>]
    def permitted_attributes
      @permitted_attributes ||= begin
        bare = base_permitted_attributes + if klass.respond_to?(:schema)
                                             admin_set_id = attributes[:admin_set_id] || attributes['admin_set_id']
                                             Bulkrax::ValkyrieObjectFactory.schema_properties(klass: klass, admin_set_id: admin_set_id).map(&:to_sym)
                                           else
                                             klass.properties.keys.map(&:to_sym)
                                           end
        (bare + nested_attributes_keys(bare)).uniq
      end
    end

    def update_work(attrs)
      attrs = HashWithIndifferentAccess.new(attrs)
      perform_transaction_for(object: object, attrs: attrs) do
        uploaded_files, file_set_params = prep_fileset_content(attrs)
        transactions["change_set.update_work"]
          .with_step_args(
            'work_resource.add_file_sets' => { uploaded_files: uploaded_files, file_set_params: file_set_params },
            'work_resource.save_acl' => { permissions_params: [attrs.try('visibility') || 'open'].compact }
          )
      end
    end

    def update_collection(attrs)
      # NOTE: We do not add relationships here; that is part of the create
      # relationships job.
      perform_transaction_for(object: object, attrs: attrs) do
        transactions['change_set.update_collection']
      end
    end

    def update_file_set(attrs)
      attrs = HashWithIndifferentAccess.new(attrs)
      remote_files = Array(attrs[:remote_files])
      raise StandardError, "#{source_identifier_value} lists #{remote_files.size} remote files; a file set takes one" if remote_files.size > 1

      parent = row_parent
      current_ids = parent ? Hyrax.query_service.find_parents(resource: object).map(&:id) : []
      reject_move_to(parent, current_ids)
      # Download before saving, so a failed download leaves the file set as it was
      path = download_file(remote_files.first[:url]) if remote_files.any?
      fs_attrs = attrs.merge(attributes).symbolize_keys
      file_set = perform_transaction_for(object: object, attrs: fs_attrs) do
        transactions['change_set.update_file_set']
      end
      file_set = replace_original_file(file_set, path, remote_files.first[:file_name]) if path
      return file_set if fs_attrs[:visibility].present? || parent.nil? || self.class.under_embargo_or_lease?(file_set)
      # Not yet attached, it takes its work's visibility from CreateRelationshipsJob, once the work is known
      return file_set if current_ids.empty?

      self.class.inherit_visibility(from: parent, to: file_set)
    end

    # A file set belongs to one work, so a re-import naming another work is rejected rather than
    # leaving the file set in both
    def reject_move_to(parent, current_ids)
      return if current_ids.empty? || current_ids.include?(parent.id)

      raise StandardError, "#{source_identifier_value} is already in work #{current_ids.first}; moving a file set to #{parent.id} is not supported"
    end

    # Replace the file set's original file with the downloaded one, and drop the old original and the
    # derivatives made from it. Storage without versions adds a second original on upload, and a file
    # set's original is whichever one is found first.
    # @return [Hyrax::FileSet]
    def replace_original_file(file_set, path, file_name)
      previous = file_set.original_file
      return file_set if previous && unchanged_file?(previous, path)

      stale = Hyrax.custom_queries.find_files(file_set: file_set).select { |file| derivative?(file) }
      # Before the upload, so the derivative jobs it starts cannot lose their output to the cleanup
      Hyrax::FileSetDerivativesService.new(file_set).cleanup_derivatives
      File.open(path) { |io| Hyrax::ValkyrieUpload.file(io: io, filename: file_name, file_set: file_set, user: @user) }
      file_set = Hyrax.query_service.find_by(id: file_set.id)
      # With versions, the upload became a new version of the same original, which stays
      stale << previous if previous && original_files(file_set).size > 1
      detach_files(file_set, stale)
    end

    # The checksum characterization records (MD5), or a SHA1 such as a migrated original may carry
    def unchanged_file?(file_metadata, path)
      (Array(file_metadata.checksum).map(&:to_s) & [Digest::MD5.file(path).hexdigest, Digest::SHA1.file(path).hexdigest]).any?
    end

    # The uses Hyrax saves generated derivatives under: thumbnails, extracted text, and audio/video service files
    def derivative?(file_metadata)
      uses = ::Valkyrie::Vocab::PCDMUse
      (Array(file_metadata.pcdm_use) & [uses.ThumbnailImage, uses.ExtractedText, uses.ServiceFile]).any?
    end

    def original_files(file_set)
      Hyrax.custom_queries.find_many_file_metadata_by_use(resource: file_set, use: Hyrax::FileMetadata::Use::ORIGINAL_FILE).to_a
    end

    def detach_files(file_set, files)
      return file_set if files.empty?

      ids = files.map { |file| file.id.to_s }
      file_set.file_ids = file_set.file_ids.reject { |id| ids.include?(id.to_s) }
      Hyrax.persister.save(resource: file_set).tap do |saved|
        Hyrax.index_adapter.save(resource: saved)
        kept = Hyrax.custom_queries.find_files(file_set: saved).map { |file| file.file_identifier.to_s }
        files.each { |file| kept.include?(file.file_identifier.to_s) ? delete_file_record(file) : transactions['file_metadata.destroy'].call(file).value! }
      end
    end

    # Disk storage keys a file by its name, so a same-named upload overwrote the old bytes in place
    # and only the record goes
    def delete_file_record(file)
      Hyrax.persister.delete(resource: file)
      Hyrax.publisher.publish('file.metadata.deleted', metadata: file)
    end

    def uploaded_local_files(uploaded_files: [])
      Array.wrap(uploaded_files).map do |file_id|
        Hyrax::UploadedFile.find(file_id)
      end
    end

    def uploaded_s3_files(remote_files: [])
      return [] if remote_files.blank?

      s3_bucket_name = ENV.fetch("STAGING_AREA_S3_BUCKET", "comet-staging-area-#{Rails.env}")
      s3_bucket = Rails.application.config.staging_area_s3_connection
                       .directories.get(s3_bucket_name)

      remote_files.map { |r| r["url"] }.map do |key|
        s3_bucket.files.get(key)
      end.compact
    end

    def uploaded_remote_files(remote_files: [])
      remote_files.map do |r|
        file_path = download_file(r["url"])
        next unless file_path
        create_uploaded_file(file_path, r["file_name"])
      end.compact
    end

    def download_file(url)
      require 'open-uri'
      require 'tempfile'

      begin
        file = Tempfile.new
        file.binmode
        file.write(URI.open(url).read)
        file.close
        # Hold the Tempfile, or garbage collection can delete it before the path is read
        (@downloads ||= []) << file
        file.path
      rescue => e
        raise "Failed to download file from #{url}: #{e.message}"
      end
    end

    def create_uploaded_file(file_path, file_name)
      file = File.open(file_path)
      uploaded_file = Hyrax::UploadedFile.create(file: file, user: @user, filename: file_name)
      file.close
      uploaded_file
    rescue => e
      raise "Failed to create Hyrax::UploadedFile for #{file_name}: #{e.message}"
    end

    # @Override Destroy existing files with Hyrax::Transactions
    def destroy_existing_files(object: @object)
      destroyed_ids = []
      Hyrax.custom_queries.find_child_file_sets(resource: object).each do |fs|
        transactions["file_set.destroy"]
          .with_step_args("file_set.remove_from_work" => { user: @user },
                          "file_set.delete" => { user: @user })
          .call(fs)
          .value!
        destroyed_ids << fs.id
      end
      return if destroyed_ids.empty?

      object.member_ids -= destroyed_ids
      object.rendering_ids = []
      object.representative_id = nil
      object.thumbnail_id = nil
    end

    def transform_attributes(update: false)
      attrs = super.merge(alternate_ids: [source_identifier_value])
                   .symbolize_keys

      attrs[:title] = [] if attrs[:title].blank?
      attrs = convert_based_near_to_attributes(attrs)
      attrs
    end

    # Hyrax's ResourceForm strips the plain `based_near` key during validation
    # (BasedNearFieldBehavior#deserialize calls params.except('based_near')).
    # Values must be passed as `based_near_attributes` — a numbered hash of
    # { "0" => { "id" => uri, "_destroy" => "false" } } — so the populator
    # can set them. Hyrax accepts any valid URI; note that only GeoNames URIs
    # will resolve to a display label via LocationService.
    def convert_based_near_to_attributes(attrs)
      values = Array.wrap(attrs.delete(:based_near)).reject(&:blank?)
      return attrs if values.empty?

      invalid = values.reject { |v| v.to_s.match?(::URI::DEFAULT_PARSER.make_regexp) }
      if invalid.any?
        raise ::StandardError, "Invalid value(s) for location (based_near): #{invalid.join(', ')}. " \
                               "Values must be valid URIs (e.g. http://sws.geonames.org/5128581/)."
      end

      attrs[:based_near_attributes] = values.each_with_index.to_h do |uri, i|
        [i.to_s, { "id" => uri.to_s, "_destroy" => "false" }]
      end
      attrs
    end
  end
  # rubocop:enable Metrics/ClassLength
end
