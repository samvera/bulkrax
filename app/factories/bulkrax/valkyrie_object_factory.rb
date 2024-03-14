# frozen_string_literal: true

module Bulkrax
  # rubocop:disable Metrics/ClassLength
  class ValkyrieObjectFactory < ObjectFactory
    include ObjectFactoryInterface

    def self.find(id)
      if defined?(Hyrax)
        begin
          Hyrax.query_service.find_by(id: id)
          # Because Hyrax is not a hard dependency, we need to transform the Hyrax exception into a
          # common exception so that callers can handle a generalize exception.
        rescue Hyrax::ObjectNotFoundError => e
          raise ObjectFactoryInterface::ObjectNotFoundError, e.message
        end
      else
        # NOTE: Fair warning; you might might need a custom query for find by alternate id.
        Valkyrie.query_service.find_by(id: id)
      end
    rescue Valkyrie::Persistence::ObjectNotFoundError => e
      raise ObjectFactoryInterface::ObjectNotFoundError, e.message
    end

    def self.solr_name(field_name)
      # It's a bit unclear what this should be if we can't rely on Hyrax.
      raise NotImplementedError, "#{self}.#{__method__}" unless defined?(Hyrax)
      Hyrax.config.index_field_mapper.solr_name(field_name)
    end

    def self.query(q, **kwargs)
      # Someone could choose ActiveFedora::SolrService.  But I think we're
      # assuming Valkyrie is specifcally working for Hyrax.  Someone could make
      # another object factory.
      raise NotImplementedError, "#{self}.#{__method__}" unless defined?(Hyrax)
      Hyrax::SolrService.query(q, **kwargs)
    end

    def self.save!(resource:, user:, persister: Hyrax.persister, index_adapter: Hyrax.index_adapter)
      if resource.respond_to?(:save!)
        resource.save!
      else
        result = persister.save(resource: resource)
        raise Valkyrie::Persistence::ObjectNotFoundError unless result
        index_adapter.save(resource: result)
        if result.collection?
          Hyrax.publisher.publish('collection.metadata.updated', collection: result, user: user)
        else
          Hyrax.publisher.publish('object.metadata.updated', object: result, user: user)
        end
        resource
      end
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
    def self.search_by_property(value:, klass:, field: nil, name_field: nil, **)
      name_field ||= field
      raise "Expected named_field or field got nil" if name_field.blank?

      # Return nil or a single object.
      Hyrax.query_service.custom_query.find_by_model_and_property_value(model: klass, property: name_field, value: value)
    end
    # rubocop:enable Metrics/ParameterLists

    ##
    # Retrieve properties from M3 model
    # @param klass the model
    # @return [Array<String>]
    def self.schema_properties(klass)
      @schema_properties_map ||= {}

      klass_key = klass.name
      @schema_properties_map[klass_key] = klass.schema.map { |k| k.name.to_s } unless @schema_properties_map.key?(klass_key)

      @schema_properties_map[klass_key]
    end

    def self.ordered_file_sets_for(object)
      return [] if object.blank?

      Hyrax.custom_queries.find_child_file_sets(resource: object)
    end

    def run!
      run
      return object if object.persisted?

      raise(ObjectFactoryInterface::RecordInvalid, object)
    end

    def find_by_id
      Hyrax.query_service.find_by(id: attributes[:id]) if attributes.key? :id
    end

    def create
      attrs = transform_attributes
              .merge(alternate_ids: [source_identifier_value])
              .symbolize_keys

      attrs[:title] = [''] if attrs[:title].blank?
      attrs[:creator] = [''] if attrs[:creator].blank?

      object = klass.new
      @object = case object
                when Bulkrax.collection_model_class
                  create_collection(object: object, attrs: attrs)
                when Bulkrax.file_model_class
                  # TODO: create_file_set(object: object, attrs: attrs)
                when Hyrax::Resource
                  create_work(object: object, attrs: attrs)
                else
                  raise "Unable to handle #{klass} for #{self.class}##{__method__}"
                end
    end

    def create_work(object:, attrs:)
      perform_transaction_for(object: object, attrs: attrs) do
        transactions["work_resource.create_with_bulk_behavior"]
          .with_step_args(
            "work_resource.add_to_parent" => { parent_id: attrs[related_parents_parsed_mapping], user: @user },
            'work_resource.add_file_sets' => { uploaded_files: get_files(attrs), user: @user },
            "change_set.set_user_as_depositor" => { user: @user },
            "work_resource.change_depositor" => { user: @user },
            'work_resource.save_acl' => { permissions_params: [attrs['visibility'] || 'open'].compact }
          )
      end
    end

    def create_collection(object:, attrs:)
      perform_transaction_for(object: object, attrs: attrs) do
        transactions['change_set.create_collection']
          .with_step_args(
            'change_set.set_user_as_depositor' => { user: @user },
            'change_set.add_to_collections' => { collection_ids: Array(attrs[related_parents_parsed_mapping]) },
            'collection_resource.apply_collection_type_permissions' => { user: @user }
          )
      end
    end

    def update
      raise "Object doesn't exist" unless @object

      conditionally_destroy_existing_files
      attrs = transform_attributes(update: true)

      @object = case @object
                when Bulkrax.collection_model_class
                  # TODO: update_collection(attrs)
                when Bulkrax.file_model_class
                  # TODO: update_file_set(attrs)
                when Hyrax::Resource
                  update_work(object: @object, attrs: attrs)
                else
                  raise "Unable to handle #{klass} for #{self.class}##{__method__}"
                end
    end

    def update_work(object:, attrs:)
      perform_transaction_for(object: object, attrs: attrs) do
        transactions["work_resource.update_with_bulk_behavior"]
          .with_step_args(
            'work_resource.add_file_sets' => { uploaded_files: get_files(attrs), user: @user },
            'work_resource.save_acl' => { permissions_params: [attrs.try('visibility') || 'open'].compact }
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

    def get_files(attrs)
      get_local_files(uploaded_files: attrs[:uploaded_files]) + get_s3_files(remote_files: attrs[:remote_files])
    end

    def get_local_files(uploaded_files: [])
      Array.wrap(uploaded_files).map do |file_id|
        Hyrax::UploadedFile.find(file_id)
      end
    end

    def get_s3_files(remote_files: {})
      return [] if remote_files.blank?

      s3_bucket_name = ENV.fetch("STAGING_AREA_S3_BUCKET", "comet-staging-area-#{Rails.env}")
      s3_bucket = Rails.application.config.staging_area_s3_connection
                       .directories.get(s3_bucket_name)

      remote_files.map { |r| r["url"] }.map do |key|
        s3_bucket.files.get(key)
      end.compact
    end

    ##
    # We accept attributes based on the model schema
    def permitted_attributes
      return Bulkrax::ValkyrieObjectFactory.schema_properties(klass) if klass.respond_to?(:schema)
      # fallback to support ActiveFedora model name
      klass.properties.keys.map(&:to_sym) + base_permitted_attributes
    end

    def apply_depositor_metadata(object, user)
      object.depositor = user.email
      object = Hyrax.persister.save(resource: object)
      Hyrax.publisher.publish("object.metadata.updated", object: object, user: @user)
      object
    end

    # @Override remove branch for FileSets replace validation with errors
    def new_remote_files
      @new_remote_files ||= if @object.is_a? Bulkrax.file_model_class
                              parsed_remote_files.select do |file|
                                # is the url valid?
                                is_valid = file[:url]&.match(URI::ABS_URI)
                                # does the file already exist
                                is_existing = @object.import_url && @object.import_url == file[:url]
                                is_valid && !is_existing
                              end
                            else
                              parsed_remote_files.select do |file|
                                file[:url]&.match(URI::ABS_URI)
                              end
                            end
    end

    def conditionally_destroy_existing_files
      return unless @replace_files

      if klass < Valkyrie::Resource
        destroy_existing_files
      elsif [Bulkrax.collection_model_class, Bulkrax.file_model_class].include?(klass)
        return
      else 
        raise "Unexpected #{klass} for #{self.class}##{__method__}"
      end
    end

    # @Override Destroy existing files with Hyrax::Transactions
    def destroy_existing_files
      existing_files = fetch_child_file_sets(resource: @object)

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

    def delete(user)
      obj = find
      return false unless obj

      Hyrax.persister.delete(resource: obj)
      Hyrax.index_adapter.delete(resource: obj)
      Hyrax.publisher.publish('object.deleted', object: obj, user: user)
    end

    private

    # Query child FileSet in the resource/object
    def fetch_child_file_sets(resource:)
      Hyrax.custom_queries.find_child_file_sets(resource: resource)
    end

    ##
    # @api public
    #
    # @return [#[]] a resolver for Hyrax's Transactions; this *should* be a
    #   thread-safe {Dry::Container}, but callers to this method should strictly
    #   use +#[]+ for access.
    #
    # @example
    #   transactions['change_set.create_work'].call(my_form)
    #
    # @see Hyrax::Transactions::Container
    # @see Hyrax::Transactions::Transaction
    # @see https://dry-rb.org/gems/dry-container
    def transactions
      Hyrax::Transactions::Container
    end
  end
  # rubocop:enable Metrics/ClassLength
end
