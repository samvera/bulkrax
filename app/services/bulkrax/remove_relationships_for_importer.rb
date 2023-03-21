# frozen_string_literal: true
module Bulkrax
  # This module is rather destructive; it will break relationships between the works, file sets, and
  # collections that were imported via an importer.  You probably don't want to run this on your
  # data, except in the case where you have been testing a Bulkrax::Importer, the parsers and
  # mappings.  Then, you might have relationships that you want to remove.
  #
  # tl;dr - Caution this will break things!
  class RemoveRelationshipsForImporter
    # @api public
    #
    # Remove the relationships of the works and collections for all of the Bulkrax::Entry records
    # associated with the given Bulkrax::Importer.
    #
    # @param importer [Bulkrax::Importer]
    # @param with_progress_bar [Boolean]
    def self.break_relationships_for!(importer:, with_progress_bar: false)
      entries = importer.entries.select(&:succeeded?)
      progress_bar = build_progress_bar_for(with_progress_bar: with_progress_bar, entries: entries)
      new(progress_bar: progress_bar, entries: entries).break_relationships!
    end

    # @api private
    #
    # A null object that conforms to this class's use of a progress bar.
    module NullProgressBar
      def self.increment; end
    end

    # @api private
    #
    # @return [#increment]
    def self.build_progress_bar_for(with_progress_bar:, entries:)
      return NullProgressBar unless with_progress_bar

      begin
        require 'ruby-progressbar'
        ProgessBar.create(total: entries.count)
      rescue LoadError
        Rails.logger.info("Using NullProgressBar because ProgressBar is not available due to a LoadError.")
      end
    end

    # @param entries [#each]
    # @param progress_bar [#increment]
    def initialize(entries:, progress_bar:)
      @progress_bar = progress_bar
      @entries = entries
    end

    attr_reader :entries, :progress_bar

    def break_relationships!
      entries.each do |entry|
        progress_bar.increment

        obj = entry.factory.find
        next if obj.is_a?(Bulkrax.file_model_class) # FileSets must be attached to a Work

        if obj.is_a?(Collection)
          remove_relationships_from_collection(obj)
        else
          remove_relationships_from_work(obj)
        end

        obj.try(:reindex_extent=, Hyrax::Adapters::NestingIndexAdapter::LIMITED_REINDEX) if defined?(Hyrax)
        obj.save!
      end
    end

    def remove_relationships_from_collection(collection)
      # Remove child work relationships
      collection.member_works.each do |work|
        change = work.member_of_collections.delete(collection)
        work.save! if change.present?
      end

      return if defined?(Hyrax)

      # Remove parent collection relationships
      collection.member_of_collections.each do |parent_col|
        Hyrax::Collections::NestedCollectionPersistenceService
          .remove_nested_relationship_for(parent: parent_col, child: collection)
      end

      # Remove child collection relationships
      collection.member_collections.each do |child_col|
        Hyrax::Collections::NestedCollectionPersistenceService
          .remove_nested_relationship_for(parent: collection, child: child_col)
      end
    end

    def remove_relationships_from_work(work)
      # Remove parent collection relationships
      work.member_of_collections = []

      # Remove parent work relationships
      work.member_of_works.each do |parent_work|
        parent_work.members.delete(work)
        parent_work.save!
      end

      # Remove child work relationships
      work.member_works.each do |child_work|
        work.member_works.delete(child_work)
      end
    end
  end
end
