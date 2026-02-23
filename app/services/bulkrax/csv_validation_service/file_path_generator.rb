# frozen_string_literal: true

module Bulkrax
  # Utility classes
  class CsvValidationService::FilePathGenerator
    TEMPLATE_PREFIX = 'import_template'

    def self.default_path(admin_set_id)
      context = load_context(admin_set_id)
      tenant = load_tenant
      filename = build_filename(context, tenant)
      path = Rails.root.join('tmp', 'imports', filename)
      FileUtils.mkdir_p(path.dirname.to_s)
      path
    end

    def self.load_context(admin_set_id)
      return nil if admin_set_id.blank?

      admin_set = Bulkrax.object_factory.find(admin_set_id)
      admin_set.respond_to?(:contexts) ? admin_set.contexts.first : nil
    end

    def self.load_tenant
      return nil unless defined?(Apartment::Tenant) && defined?(Account)

      tenant_id = Apartment::Tenant.current
      return nil if tenant_id.blank?

      Account.find_by(tenant: tenant_id)&.name
    end

    def self.build_filename(context, tenant)
      parts = [TEMPLATE_PREFIX]
      parts << "context-#{context}" if context.present?
      parts << "tenant-#{tenant}" if tenant.present?
      parts << timestamp
      "#{parts.join('_')}.csv"
    end

    def self.timestamp
      Time.current.utc.strftime('%Y%m%d_%H%M%S')
    end
  end
end
