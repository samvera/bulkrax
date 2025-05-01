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
    # @note This does not save either object.  We need to do that in another
    #       loop.  Why?  Because we might be adding many items to the parent.
    def self.add_child_to_parent_work(parent:, child:)
      return true if parent.member_ids.include?(child.id)

      parent.member_ids << child.id
      parent.save
    end

    def self.add_resource_to_collection(collection:, resource:, user:)
      resource.member_of_collection_ids << collection.id
      save!(resource: resource, user: user)
    end

    def self.field_multi_value?(field:, model:)
      return false unless field_supported?(field: field, model: model)

      if model.respond_to?(:schema)
        schema = model.new.singleton_class.schema || model.schema
        dry_type = schema.key(field.to_sym)
        return true if dry_type.respond_to?(:primitive) && dry_type.primitive == Array

        false
      else
        Bulkrax::ObjectFactory.field_multi_value?(field: field, model: model)
      end
    end

    def self.field_supported?(field:, model:)
      if model.respond_to?(:schema)
        schema_properties(model).include?(field)
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
    rescue Hyrax::ObjectNotFoundError => e
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
      if resource.respond_to?(:save!)
        resource.save!
      else
        result = Hyrax.persister.save(resource: resource)
        raise Valkyrie::Persistence::ObjectNotFoundError unless result
        Hyrax.index_adapter.save(resource: result)
        if result.collection?
          publish('collection.metadata.updated', collection: result, user: user)
        else
          publish('object.metadata.updated', object: result, user: user)
        end
        resource
      end
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
    # Retrieve properties from M3 model
    # @param klass the model
    # @return [Array<String>]
    def self.schema_properties(klass)
      @schema_properties_map ||= {}

      klass_key = klass.name
      schema = klass.new.singleton_class.schema || klass.schema
      @schema_properties_map[klass_key] = schema.map { |k| k.name.to_s } 

      @schema_properties_map[klass_key]
    end

    def self.ordered_file_sets_for(object)
      return [] if object.blank?

      Hyrax.custom_queries.find_child_file_sets(resource: object)
    end

    def delete(user)
      obj = find
      return false unless obj

      Hyrax.persister.delete(resource: obj)
      Hyrax.index_adapter.delete(resource: obj)
      self.class.publish(event: 'object.deleted', object: obj, user: user)
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
      self.class.publish(event: "object.metadata.updated", object: object, user: @user)
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

    def create_file_set(attrs)
      # TODO: Make it work for Valkyrie
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
      Hyrax.query_service.find_by(id: attributes[:id]) if attributes.key? :id
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
      form = Hyrax::Forms::ResourceForm.for(object).prepopulate!

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
    # We accept attributes based on the model schema
    #
    # @return [Array<Symbols>]
    def permitted_attributes
      @permitted_attributes ||= (
        base_permitted_attributes + if klass.respond_to?(:schema)
                                      Bulkrax::ValkyrieObjectFactory.schema_properties(klass)
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
      # TODO: Make it work
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
    def destroy_existing_files
      existing_files = Hyrax.custom_queries.find_child_file_sets(resource: object)

      existing_files.each do |fs|
        transactions["file_set.destroy"]
          .with_step_args("file_set.remove_from_work" => { user: @user },
                          "file_set.delete" => { user: @user })
          .call(fs)
          .value!
      end

      @object.member_ids = @object.member_ids.reject { |m| existing_files.detect { |f| f.id == m } }
      @object.rendering_ids = []
      @object.representative_id = nil
      @object.thumbnail_id = nil
    end

    def transform_attributes(update: false)
      attrs = super.merge(alternate_ids: [source_identifier_value])
                   .symbolize_keys

      attrs[:title] = [''] if attrs[:title].blank?
      attrs[:creator] = [''] if attrs[:creator].blank?
      attrs
    end
  end
  # rubocop:enable Metrics/ClassLength
end
