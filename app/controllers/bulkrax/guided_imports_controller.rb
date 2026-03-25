# frozen_string_literal: true

module Bulkrax
  class GuidedImportsController < ::Bulkrax::ApplicationController
    include Hyrax::ThemedLayoutController if defined?(::Hyrax)
    include Bulkrax::GuidedImportDemoScenarios if Bulkrax.config.guided_import_demo_scenarios_enabled
    include Bulkrax::ImporterFileHandler
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
      render json: StepperResponseFormatter.format(run_validation(csv_file, zip_file, admin_set_id: admin_set_id)), status: :ok
    ensure
      close_file_handles(files)
    end

    def create
      files = nil
      files = resolve_create_files
      return render_invalid_uploaded_files_response if params[:uploaded_files].present? && files.empty?

      @importer = Importer.new(importer_params)
      @importer.parser_klass = 'Bulkrax::CsvParser'
      @importer.user = current_user if respond_to?(:current_user) && current_user.present?
      apply_field_mapping

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

    def render_invalid_uploaded_files_response
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: ['No valid uploaded files found'] }, status: :unprocessable_entity }
      end
    end

    # Runs validation via the real service.
    # @param csv_file [File, StringIO] the CSV to validate
    # @param zip_file [File, nil] an optional ZIP containing file attachments
    # @param admin_set_id [String, nil] optional admin set ID for validation context
    # @return [Hash] validation result data
    def run_validation(csv_file, zip_file, admin_set_id: nil)
      CsvValidationService.validate(csv_file: csv_file, zip_file: zip_file, admin_set_id: admin_set_id)
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
