# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ClassLength
  class ValkyrieObjectFactory < ObjectFactoryInterface
    class FileFactoryInnerWorkings < Bulkrax::FileFactory::InnerWorkings
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
      return true if parent.member_ids.include?(child.id)
      parent.member_ids += [child.id]
      Hyrax.persister.save(resource: parent)
    end

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
      cached_schema_for(klass: klass, admin_set_id: admin_set_id).map { |k| k.name.to_s }
    end

    ##
    # Returns the schema for a model, memoized per (klass, admin_set_id) pair.
    # Delegates to +Hyrax.schema_for+ when available so that context-gated
    # properties are included without Bulkrax knowing about flexibility internals.
    #
    # @param klass [Class]
    # @param admin_set_id [String, nil]
    # @return [Dry::Types::Hash]
    def self.cached_schema_for(klass:, admin_set_id: nil)
      @cached_schema_map ||= {}
      key = [klass.name, admin_set_id].compact.join('|')
      @cached_schema_map[key] ||=
        if admin_set_id.present? && defined?(Hyrax) && Hyrax.respond_to?(:schema_for)
          Hyrax.schema_for(klass: klass, admin_set_id: admin_set_id)
        else
          klass.new.singleton_class.schema || klass.schema
        end
    end

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

    # @note We perform the transaction against the *parent* here, because the FileSets are generated and updated in relationship with their parent, not in isolation
    def create_file_set(attrs)
      attrs = HashWithIndifferentAccess.new(attrs)
      parent_object = find_record(attributes[related_parents_parsed_mapping].first, importer_run_id).last
      perform_transaction_for(object: parent_object, attrs: {}) do
        fs_attrs = attrs.merge(attributes).symbolize_keys
        uploaded_files, = prep_fileset_content(attrs)
        transactions['change_set.update_work']
          .with_step_args(
            'work_resource.add_file_sets' => { uploaded_files: uploaded_files, file_set_params: [fs_attrs] },
            'work_resource.save_acl' => { permissions_params: [attrs.try('visibility') || 'open'].compact }
          )
      end
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
        file_attrs << ({ uploaded_file_id: f["id"].to_s, filename: files[index]["file_name"] }).merge(additional_attributes[index])
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

    def find_by_id
      self.class.find(attributes[:id]) if attributes.key? :id
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
      @permitted_attributes ||= (
        base_permitted_attributes + if klass.respond_to?(:schema)
                                      admin_set_id = attributes[:admin_set_id] || attributes['admin_set_id']
                                      Bulkrax::ValkyrieObjectFactory.schema_properties(klass: klass, admin_set_id: admin_set_id)
                                    else
                                      klass.properties.keys.map(&:to_sym)
                                    end
      ).uniq
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
      fs_attrs = attrs.merge(attributes).symbolize_keys
      perform_transaction_for(object: object, attrs: fs_attrs) do
        prep_fileset_content(attrs)
        transactions['change_set.update_file_set']
      end
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
        file.rewind
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
      existing_files = Hyrax.custom_queries.find_child_file_sets(resource: object)
      return if existing_files.empty?

      existing_files.each do |fs|
        transactions["file_set.destroy"]
          .with_step_args("file_set.remove_from_work" => { user: @user },
                          "file_set.delete" => { user: @user })
          .call(fs)
          .value!
      end

      object.member_ids = object.member_ids.reject { |m| existing_files.detect { |f| f.id == m } }
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
    # can set them. CSV values in the `location` column must be GeoNames URIs.
    def convert_based_near_to_attributes(attrs)
      values = Array.wrap(attrs.delete(:based_near)).reject(&:blank?)
      return attrs if values.empty?

      invalid = values.reject { |v| v.to_s.match?(::URI::DEFAULT_PARSER.make_regexp) }
      if invalid.any?
        raise ::StandardError, "Invalid value(s) for location (based_near): #{invalid.join(', ')}. " \
                               "Values must be GeoNames URIs (e.g. http://sws.geonames.org/5128581/)."
      end

      attrs[:based_near_attributes] = values.each_with_index.to_h do |uri, i|
        [i.to_s, { "id" => uri.to_s, "_destroy" => "false" }]
      end
      attrs
    end
  end
  # rubocop:enable Metrics/ClassLength
end
