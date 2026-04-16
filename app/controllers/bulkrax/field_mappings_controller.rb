# frozen_string_literal: true

module Bulkrax
  class FieldMappingsController < ::Bulkrax::ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    with_themed_layout 'dashboard' if defined?(::Hyrax)

    before_action :authenticate_user!

    ADVANCED_PROPERTIES = %w[
      search_field parsed object nested_type join
      related_children_field_mapping related_parents_field_mapping
      if skip_object_for_model_names
    ].freeze

    def edit
      @all_mappings = load_mappings
      @parsers = @all_mappings.keys
      @selected_parser = params[:parser].presence || @parsers.first || "Bulkrax::CsvParser"

      if params[:reset].present?
        defaults = default_mappings
        @all_mappings[@selected_parser] = defaults[@selected_parser] || {}
        save_mappings(@all_mappings)
        redirect_to edit_field_mappings_path(parser: @selected_parser), notice: t('bulkrax.field_mappings.flash.reset')
        return
      end

      @mappings = @all_mappings[@selected_parser] || {}
      add_breadcrumbs
    end

    def update
      all_mappings = JSON.parse(params[:full_mappings_json])
      parser = params[:parser]

      parser_mappings = {}
      errors = []

      source_id_fields = []

      (params[:mappings] || {}).each_value do |field_data|
        name = field_data[:name].to_s.strip
        next if name.blank?

        unless name.match?(/\A[a-zA-Z0-9_]+\z/)
          errors << t('bulkrax.field_mappings.validations.invalid_field_name', name: name)
          next
        end

        if parser_mappings.key?(name)
          errors << t('bulkrax.field_mappings.validations.duplicate_field', name: name)
          next
        end

        entry = build_entry(field_data)
        source_id_fields << name if entry[:source_identifier]

        if entry[:from].blank? && !entry[:generated]
          errors << t('bulkrax.field_mappings.validations.from_or_generated', name: name)
          next
        end

        if_method = field_data[:if_method].to_s.strip
        if_regex = field_data[:if_regex].to_s.strip
        if (if_method.present? && if_regex.blank?) || (if_method.blank? && if_regex.present?)
          errors << t('bulkrax.field_mappings.validations.if_incomplete', name: name)
          next
        end

        if field_data[:nested_type].to_s.strip.present? && field_data[:object].to_s.strip.blank?
          errors << t('bulkrax.field_mappings.validations.nested_type_without_object', name: name)
          next
        end

        parser_mappings[name] = entry
      end

      if source_id_fields.size > 1
        errors << t('bulkrax.field_mappings.validations.single_source_identifier', fields: source_id_fields.join(', '))
      end

      if errors.any?
        @all_mappings = all_mappings
        @parsers = all_mappings.keys
        @selected_parser = parser
        @mappings = parser_mappings
        @errors = errors
        add_breadcrumbs
        render :edit
        return
      end

      all_mappings[parser] = parser_mappings
      save_mappings(all_mappings)

      redirect_to edit_field_mappings_path(parser: parser), notice: t('bulkrax.field_mappings.flash.updated')
    end

    protected

    # Override in host app to load tenant-specific mappings
    def load_mappings
      Bulkrax.field_mappings.deep_dup
    end

    # Override in host app to persist mappings
    def save_mappings(hash)
      Bulkrax.field_mappings = hash
    end

    # Override in host app to provide default mappings for reset
    def default_mappings
      Bulkrax.field_mappings.deep_dup
    end

    private

    def build_entry(field_data)
      from_value = field_data[:from].to_s.strip
      from = from_value.present? ? from_value.split(',').map(&:strip) : []

      split_value = if ActiveModel::Type::Boolean.new.cast(field_data[:split])
                      regex = field_data[:split_regex].to_s.strip
                      regex.present? ? regex : true
                    else
                      false
                    end

      entry = {
        from: from,
        split: split_value,
        generated: ActiveModel::Type::Boolean.new.cast(field_data[:generated]) || false,
        source_identifier: ActiveModel::Type::Boolean.new.cast(field_data[:source_identifier]) || false,
        excluded: ActiveModel::Type::Boolean.new.cast(field_data[:excluded]) || false
      }

      # Advanced properties
      %w[search_field object nested_type].each do |prop|
        val = field_data[prop].to_s.strip
        entry[prop.to_sym] = val if val.present?
      end

      %w[parsed join related_children_field_mapping related_parents_field_mapping].each do |prop|
        entry[prop.to_sym] = true if ActiveModel::Type::Boolean.new.cast(field_data[prop])
      end

      if_method = field_data[:if_method].to_s.strip
      if_regex = field_data[:if_regex].to_s.strip
      entry[:if] = [if_method, if_regex] if if_method.present? && if_regex.present?

      skip_models = field_data[:skip_object_for_model_names].to_s.strip
      entry[:skip_object_for_model_names] = skip_models.split(',').map(&:strip) if skip_models.present?

      entry
    end

    def add_breadcrumbs
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path if defined?(::Hyrax)
      add_breadcrumb t(:'hyrax.dashboard.title'), hyrax.dashboard_path if defined?(::Hyrax)
      add_breadcrumb t('bulkrax.field_mappings.breadcrumb')
    end
  end
end
