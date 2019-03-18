require 'language_list'
require 'erb'
require 'ostruct'

module Bulkrax
  class ApplicationMapping
    attr_accessor :record, :rights_statement, :override_rights_statement, :contributing_institution, :thumbnail_url, :all
    class_attribute :matchers

    def initialize(record, rights_statement, override_rights_statement, contributing_institution, thumbnail_url, all = false)
      @record = record.record
      @rights_statement = rights_statement
      @override_rights_statement = (override_rights_statement == "1")
      @contributing_institution = contributing_institution
      @thumbnail_url = thumbnail_url
      @all = all
    end

    def self.matcher(name, args={})
      self.matchers ||= {}
      from = args[:from] || [name]

      matcher = matcher_class.new(
        to: name,
        from: from,
        parsed: args[:parsed],
        split: args[:split],
        if: args[:if]
      )

      from.each do |lookup|
        self.matchers[lookup] = matcher
      end
    end

    def metadata
      return @metadata if @metadata

      @metadata = {}
      record.metadata.children.each do |child|
        child.children.each do |node|
          add_metadata(node.name, node.content)
        end
      end
      # TODO go through all parer_fields and add them?
      add_metadata('thumbnail_url', thumbnail_url)
      @metadata['contributing_institution'] = [contributing_institution]
      if override_rights_statement || @metadata['rights_statement'].blank?
        @metadata['rights_statement'] = [rights_statement]
      end
      @metadata['visibility'] = 'open'

      @metadata
    end

    def add_metadata(node_name, node_content)
      matcher = self.class.matchers[node_name]

      if matcher
        result = matcher.result(self, node_content)
        if result
          key = matcher.to
          @metadata[key] ||= []

          if result.is_a?(Array)
            @metadata[key] += result
          else
            @metadata[key] << result
          end
        end
      end
    end

    def all_attrs
      merge_attrs(header, metadata)
    end

    def context
      @context ||= OpenStruct.new(record: record, identifier: record.header.identifier)
    end

    def thumbnail_url
      ERB.new(@thumbnail_url).result(context.instance_eval { binding })
    end

    def header
      {
        'source' => [record.header.identifier]
      }
    end

    def merge_attrs(first, second)
      return first if second.blank?

      first = {} if first.blank?

      first.merge(second) do |key, old, new|
        if key =~ /identifier/
          merged_value = old if old.first =~ /^http/
          merged_value = new if new.first =~ /^http/
        else
          merged_value = old + new
        end
        merged_value
      end
    end

  end
end
