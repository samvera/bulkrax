require 'iso8601'

module Bulkrax
  class Importer < ApplicationRecord
    serialize :parser_fields, JSON
    serialize :field_mapping, JSON

    belongs_to :user
    has_many :importer_runs, dependent: :destroy, foreign_key: 'bulkrax_importer_id'
    has_many :entries, dependent: :destroy, foreign_key: 'bulkrax_importer_id'

    validates :name, presence: true
    validates :admin_set_id, presence: true

    attr_accessor :only_updates
    # TODO validates :metadata_prefix, presence: true
    # TODO validates :base_url, presence: true

    def parser_fields
      read_attribute(:parser_fields) || {}
    end

    def parser
      # create an parser based on importer
      @parser ||= self.parser_klass.constantize.new(self)
    end

    def frequency_enums
      # these duration values use ISO 8601 Durations (https://en.wikipedia.org/wiki/ISO_8601#Durations)
      # TLDR; all durations are prefixed with 'P' and the parts are a number with the type of duration.
      # i.e. P1Y2M3W4DT5H6M7S == 1 Year, 2 Months, 3 Weeks, 4 Days, 5 Hours, 6 Minutes, 7 Seconds
      [['Daily', 'P1D'], ['Monthly', 'P1M'], ['Yearly', 'P1Y'], ['Once (on save)', 'PT0S']]
    end

    def frequency=(frequency)
      write_attribute(:frequency, ISO8601::Duration.new(frequency).to_s)
    end

    def frequency
      f = read_attribute(:frequency) || "PT0S"
      ISO8601::Duration.new(f)
    end

    def schedulable?
      frequency.to_seconds != 0
    end

    def last_imported_at
      @last_imported_at ||= self.importer_runs.last&.created_at
    end

    def next_import_at
      (last_imported_at || Time.current) + frequency.to_seconds if schedulable? and last_imported_at.present?
    end

    def current_importer_run
      @current_importer_run ||= self.importer_runs.create!(total_records: self.limit)
    end

    def seen
      @seen ||= {}
    end

    def import_works(only_updates=false)
      self.only_updates = only_updates
      parser.run
      remove_unseen
    end

    def remove_unseen
      # TODO
      # if primary_collection
      #   primary_collection.member_ids.each do |id|
      #     w = Work.find id
      #     unless seen[w.source[0]]
      #       if w.in_collections.size > 1
      #         primary_collection.members.delete w # only removes from primary collection - wants the record, not the id
      #         primary_collection.save
      #       else
      #         w.delete # removes from all collections
      #       end
      #     end
      #   end
      # end
    end

    def increment_counters(index)
      if limit.to_i > 0
        current_importer_run.total_records = limit
      elsif parser.total > 0
        current_importer_run.total_records = parser.total
      else
        current_importer_run.total_records = index + 1
      end
      current_importer_run.enqueued_records = index + 1
      current_importer_run.save!
    end

  end
end
