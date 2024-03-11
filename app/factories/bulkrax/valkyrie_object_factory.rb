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
      # TODO: Downstream implementers will need to figure this out.
      raise NotImplementedError, "#{self}.#{__method__}" unless defined?(Hyrax)
      Hyrax.config.index_field_mapper.solr_name(field_name)
    end

    def self.query(q, **kwargs)
      # TODO: Without the Hyrax::SolrService, what are we left with?  Someone could choose
      # ActiveFedora::SolrService.
      raise NotImplementedError, "#{self}.#{__method__}" unless defined?(Hyrax)
      Hyrax::SolrService.query(q, **kwargs)
    end

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

    def search_by_identifier
      # Query can return partial matches (something6 matches both something6 and something68)
      # so we need to weed out any that are not the correct full match. But other items might be
      # in the multivalued field, so we have to go through them one at a time.
      match = Hyrax.query_service.custom_queries.find_by_source_identifier(
        work_identifier: work_identifier,
        source_identifier_value: source_identifier_value
      )

      return match if match
    rescue => err
      Hyrax.logger.error(err)
      false
    end

    def create
      attrs = transform_attributes
              .merge(alternate_ids: [source_identifier_value])
              .symbolize_keys

      attrs[:title] = [''] if attrs[:title].blank?
      attrs[:creator] = [''] if attrs[:creator].blank?

      object = klass.new
      @object = case object
                when Hyrax::PcdmCollection
                  create_collection(object: object, attrs: attrs)
                when Hyrax::FileSet
                  # TODO
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
            "work_resource.add_bulkrax_files" =>  { files: get_files(attrs) }, #get_s3_files(remote_files: attrs["remote_files"]), user: @user },
            "change_set.set_user_as_depositor" => { user: @user },
            "work_resource.change_depositor" => { user: @user },
            'work_resource.save_acl' => { permissions_params: [attrs.try('visibility') || 'open'].compact }
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
                when Hyrax::PcdmCollection
                  # update_collection(attrs)
                when Hyrax::FileSet
                  # TODO
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
                        "work_resource.add_bulkrax_files" => { files: get_files(attrs) }, # get_s3_files(remote_files: attrs["remote_files"]), user: @user }
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

      # result = transaction.call(form)
      result = transaction.call(form, files: @files, user: @user)

      result.value_or do
        msg = result.failure[0].to_s
        msg += " - #{result.failure[1].full_messages.join(',')}" if result.failure[1].respond_to?(:full_messages)
        raise StandardError, msg, result.trace
      end
    end

    def get_files(attrs)
      get_local_files(attrs) #+ get_s3_files(remote_files: attrs["remote_files"])
    end

    def get_local_files(attrs)
      # byebug # what properties will we get here?
      # {:title=>["valkyrie resource 3"], :admin_set_id=>"admin_set/default", :contributor=>[], :creator=>["jg"], :description=>[], :identifier=>[], :keyword=>["bulk test"], :publisher=>[], :language=>[], :license=>[], :resource_type=>["Image"], :rights_statement=>[""], :source=>["6"], :subject=>[], :uploaded_files=>[40], :alternate_ids=>["6"]}
      # Hyrax::UploadedFile.find'40'
      return [] if attrs[:uploaded_files].blank?

      @files = attrs[:uploaded_files].map do |file_id|
        Hyrax::UploadedFile.find(file_id)
      end

      @files
    end

    def get_s3_files(remote_files: {})
      if remote_files.blank?
        Hyrax.logger.info "No remote files listed for #{attributes['source_identifier']}"
        return []
      end

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
      @new_remote_files ||= if @object.is_a? FileSet
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
    
      if [Hyrax::PcdmCollection, Hyrax::FileSet, Bulkrax::ValkyrieObjectFactory].include?(klass)
        return
      elsif klass.ancestors.include?(Valkyrie::Resource) && klass != CollectionResource
        destroy_existing_files
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
