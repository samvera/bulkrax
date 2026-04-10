# frozen_string_literal: true

module Bulkrax
  class GuidedImportsController < ::Bulkrax::ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    include Bulkrax::GuidedImportDemoScenarios if Bulkrax.config.guided_import_demo_scenarios_enabled
    include Bulkrax::ImporterFileHandler
    include Bulkrax::GuidedImportMetrics
    helper Bulkrax::ImportersHelper

    before_action :authenticate_user!
    before_action :check_permissions
    with_themed_layout 'dashboard' if defined?(::Hyrax)

    # trigger form to allow upload
    def new
      @importer = Importer.new
      return unless defined?(::Hyrax)
      add_importer_breadcrumbs
      add_breadcrumb I18n.t('bulkrax.importer.guided_import.breadcrumb')
    end

    # AJAX endpoint to validate uploaded files
    def validate
      set_locale_from_params

      files, error = resolve_validation_files
      return render json: error, status: :ok if error
      return render json: StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.no_files_uploaded')), status: :ok unless files.any?

      csv_file, zip_file = select_csv_and_zip(files)

      unless csv_file
        return render json: StepperResponseFormatter.error(message: I18n.t('bulkrax.importer.guided_import.validation.no_csv_uploaded')), status: :ok unless zip_file

        csv_file, error = extract_csv_from_zip(zip_file)
        return render json: error, status: :ok if error
      end

      admin_set_id = params[:importer]&.[](:admin_set_id)
      validation_start = Time.now.to_f
      validation_result = run_validation(csv_file, zip_file, admin_set_id: admin_set_id)
      duration_ms = ((Time.now.to_f - validation_start) * 1000).round

      record_validation_metric(validation_result, duration_ms)

      raw_csv_data = validation_result.delete(:raw_csv_data)
      cache_key = cache_validation_errors(validation_result, raw_csv_data, csv_file)
      formatted = StepperResponseFormatter.format(validation_result)
      formatted[:validationErrorsCacheKey] = cache_key
      render json: formatted, status: :ok
    ensure
      close_file_handles(files)
    end

    def download_validation_errors
      cache_key = params[:key].to_s
      expected_prefix = "guided_import_errors:#{session.id}:"
      return head :not_found unless cache_key.start_with?(expected_prefix)

      cached = Rails.cache.read(cache_key)
      return head :not_found unless cached

      csv = ValidationErrorCsvBuilder.build(
        headers: cached[:headers],
        csv_data: cached[:csv_data],
        row_errors: cached[:row_errors],
        file_errors: cached[:file_errors]
      )
      send_data csv, filename: error_csv_filename(cached[:original_filename]), type: 'text/csv', disposition: 'attachment'
    end

    def create
      files = nil
      files = resolve_create_files
      return render_invalid_uploaded_files_response if params[:uploaded_files].present? && files.empty?

      @importer = build_guided_importer

      if @importer.save
        write_files(files)
        Bulkrax::ImporterJob.perform_later(@importer.id)

        respond_to do |format|
          format.html { redirect_to bulkrax.importers_path, notice: I18n.t('bulkrax.importer.guided_import.flash.import_started') }
          format.json { render json: { success: true, importer_id: @importer.id }, status: :created }
        end
      else
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: { errors: @importer.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    ensure
      close_file_handles(files)
    end

    private

    def build_guided_importer
      @importer = Importer.new(importer_params)
      @importer.parser_klass = 'Bulkrax::CsvParser'
      @importer.user = current_user if respond_to?(:current_user) && current_user.present?
      @importer.parser_fields = (@importer.parser_fields || {}).merge('guided_import' => true)
      @importer.parser_fields['metrics_session_id'] = params[:metrics_session_id] if Bulkrax.config.guided_import_metrics_enabled && params[:metrics_session_id].present?
      apply_field_mapping
      @importer
    end

    def render_invalid_uploaded_files_response
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: ['No valid uploaded files found'] }, status: :unprocessable_entity }
      end
    end

    def run_validation(csv_file, zip_file, admin_set_id: nil)
      CsvParser.validate_csv(csv_file: csv_file, zip_file: zip_file, admin_set_id: admin_set_id)
    end

    def importer_params
      params.require(:importer).permit(
        :name,
        :admin_set_id,
        :limit,
        parser_fields: [:visibility, :rights_statement, :override_rights_statement, :import_file_path, :file_style]
      )
    end

    def apply_field_mapping
      @importer.field_mapping = Bulkrax.field_mappings['Bulkrax::CsvParser']
    end

    def error_csv_filename(original_filename)
      return 'import_errors.csv' if original_filename.blank?

      base = File.basename(original_filename, '.*')
      "#{base}_errors.csv"
    end

    def set_locale_from_params
      I18n.locale = params[:locale] if params[:locale].present? && I18n.available_locales.include?(params[:locale].to_sym)
    end

    def add_importer_breadcrumbs
      add_breadcrumb t(:'hyrax.controls.home'), main_app.root_path
      add_breadcrumb t(:'hyrax.dashboard.breadcrumbs.admin'), hyrax.dashboard_path
      add_breadcrumb 'Importers', bulkrax.importers_path
    end

    def check_permissions
      raise CanCan::AccessDenied unless current_ability.can_import_works?
    end
  end
end
