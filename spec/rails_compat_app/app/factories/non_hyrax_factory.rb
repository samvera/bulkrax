# frozen_string_literal: true

# Stands in for a non-Hyrax app's own object factory: like such an app's, it
# subclasses Bulkrax::ObjectFactory and replaces the parts that need ActiveFedora without Hyrax.
class NonHyraxFactory < Bulkrax::ObjectFactory
  def self.find(id)
    Work.find(id)
  rescue ActiveRecord::RecordNotFound => e
    raise Bulkrax::ObjectFactoryInterface::ObjectNotFoundError, e.message
  end

  # Stands in for Solr, answering the queries an export makes for works.
  def self.query(query, fq: [], **)
    query = [query, *fq].join(' ')
    return [] unless query.match?(/has_model_ssim:\(?[^)]*\bWork\b/)

    identifiers = query.scan(/"([^"]+)"/).flatten - ['Work']
    works = identifiers.empty? ? Work.all : Work.where(bulkrax_identifier: identifiers)
    works.map { |work| { 'id' => work.id.to_s } }
  end

  def self.solr_name(field_name)
    "#{field_name}_tesim"
  end

  def self.export_values(values)
    values
  end

  def self.export_value(value)
    value
  end

  def self.update_index(resources: [])
    resources
  end

  def run!
    @object = find
    object.present? ? update : create
    object
  end

  def create
    @object = klass.new(transform_attributes)
    object.save!
    log_created(object)
  end

  def update
    object.update!(transform_attributes(update: true))
    log_updated(object)
  end

  def find
    return find_by_id if attributes[:id].present?

    search_by_identifier if attributes[work_identifier].present?
  end

  def search_by_identifier
    klass.where(work_identifier => source_identifier_value).first
  end
end
