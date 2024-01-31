# frozen_string_literal: true

module Bulkrax
  class ValkyrieObjectFactory < ObjectFactory
    ##
    # Retrieve properties from M3 model
    # @param klass the model
    # return Array<string>
    def self.schema_properties(klass)
      @schema_properties_map ||= {}

      klass_key = klass.name
      @schema_properties_map[klass_key] = klass.schema.map { |k| k.name.to_s } unless @schema_properties_map.key?(klass_key)

      @schema_properties_map[klass_key]
    end

    def run!
      run
      return object if object.persisted?

      raise(RecordInvalid, object)
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

      # temporary workaround just to see if we can get the import to work
      attrs[:title] = [''] if attrs[:title].blank?
      attrs[:creator] = [''] if attrs[:creator].blank?

      cx = Hyrax::Forms::ResourceForm.for(klass.new).prepopulate!
      cx.validate(attrs)

      result = transaction_create
               .with_step_args(
          # "work_resource.add_to_parent" => {parent_id: @related_parents_parsed_mapping, user: @user},
          "work_resource.#{Bulkrax::Transactions::Container::ADD_BULKRAX_FILES}" => { files: get_s3_files(remote_files: attributes["remote_files"]), user: @user },
          "change_set.set_user_as_depositor" => { user: @user },
          "work_resource.change_depositor" => { user: @user },
          'work_resource.save_acl' => { permissions_params: [attrs.try('visibility') || 'open'].compact }
        )
               .call(cx)

      if result.failure?
        msg = result.failure[0].to_s
        msg += " - #{result.failure[1].full_messages.join(',')}" if result.failure[1].respond_to?(:full_messages)
        raise StandardError, msg, result.trace
      end

      @object = result.value!

      @object
    end

    def update
      raise "Object doesn't exist" unless @object

      destroy_existing_files if @replace_files && ![Collection, FileSet].include?(klass)

      attrs = transform_attributes(update: true)

      cx = Hyrax::Forms::ResourceForm.for(@object)
      cx.validate(attrs)

      result = transaction_update
               .with_step_args(
          "work_resource.#{Bulkrax::Transactions::Container::ADD_BULKRAX_FILES}" => { files: get_s3_files(remote_files: attributes["remote_files"]), user: @user }

          # TODO: uncomment when we upgrade Hyrax 4.x
          # 'work_resource.save_acl' => { permissions_params: [attrs.try('visibility') || 'open'].compact }
        )
               .call(cx)

      @object = result.value!
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

    # @Override Destroy existing files with Hyrax::Transactions
    def destroy_existing_files
      existing_files = fetch_child_file_sets(resource: @object)

      existing_files.each do |fs|
        Hyrax::Transactions::Container["file_set.destroy"]
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

    private

    # TODO: Rename to transaction_create
    def transaction_create
      Hyrax::Transactions::Container["work_resource.#{Bulkrax::Transactions::Container::CREATE_WITH_BULK_BEHAVIOR}"]
    end

    # Customize Hyrax::Transactions::WorkUpdate transaction with bulkrax
    def transaction_update
      Hyrax::Transactions::Container["work_resource.#{Bulkrax::Transactions::Container::UPDATE_WITH_BULK_BEHAVIOR}"]
    end

    # Query child FileSet in the resource/object
    def fetch_child_file_sets(resource:)
      Hyrax.custom_queries.find_child_file_sets(resource: resource)
    end
  end

  class RecordInvalid < StandardError
  end
end
