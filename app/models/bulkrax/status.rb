# frozen_string_literal: true

module Bulkrax
  class Status < ApplicationRecord
    belongs_to :statusable, polymorphic: true, denormalize: { fields: %i[status_message], if: :latest? }
    belongs_to :runnable, polymorphic: true
    serialize :error_backtrace, Array

    scope :for_importers, -> { where(statusable_type: 'Bulkrax::Importer') }
    scope :for_exporters, -> { where(statusable_type: 'Bulkrax::Exporter') }

    scope :latest_by_statusable, -> { joins(latest_by_statusable_subtable.join_sources) }

    def self.latest_by_statusable_subtable
      status_table = self.arel_table
      latest_status_query = status_table.project(status_table[:statusable_id],
                                                 status_table[:statusable_type],
                                                 status_table[:id].maximum.as("latest_status_id")).group(status_table[:statusable_id], status_table[:statusable_type])

      latest_status_table = Arel::Table.new(latest_status_query).alias(:latest_status)
      status_table.join(latest_status_query.as(latest_status_table.name.to_s), Arel::Nodes::InnerJoin)
                  .on(status_table[:id].eq(latest_status_table[:latest_status_id]))
    end

    def latest?
      self.id == self.class.where(statusable_id: self.statusable_id, statusable_type: self.statusable_type).order('id desc').pluck(:id).first
    end
  end
end
