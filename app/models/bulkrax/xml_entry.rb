# frozen_string_literal: true

module Bulkrax
  # Generic XML Entry
  class XmlEntry < Entry
    serialize :raw_metadata, Bulkrax::NormalizedJson

    def self.fields_from_data(data); end

    def self.read_data(path)
      # This doesn't cope with BOM sequences:
      # Nokogiri::XML(open(path), nil, 'UTF-8').remove_namespaces!
      Nokogiri::XML(open(path)).remove_namespaces!
    end

    def self.data_for_entry(data, source_id, _parser)
      collections = []
      children = []
      xpath_for_source_id = ".//*[name()='#{source_id}']"
      return {
        source_id => data.xpath(xpath_for_source_id).first.text,
        delete: data.xpath(".//*[name()='delete']").first&.text,
        data:
          data.to_xml(
            encoding: 'UTF-8',
            save_with:
              Nokogiri::XML::Node::SaveOptions::NO_DECLARATION | Nokogiri::XML::Node::SaveOptions::NO_EMPTY_TAGS
          ).delete("\n").delete("\t").squeeze(' '), # Remove newlines, tabs, and extra whitespace
        collection: collections,
        children: children
      }
    end

    # def self.matcher_class; end

    def record
      @record ||= Nokogiri::XML(self.raw_metadata['data'], nil, 'UTF-8')
    end

    def build_metadata
      raise StandardError, 'Record not found' if record.nil?
      raise StandardError, "Missing source identifier (#{source_identifier})" if self.raw_metadata[source_identifier].blank?
      self.parsed_metadata = {}
      self.parsed_metadata[work_identifier] = [self.raw_metadata[source_identifier]]

      # We need to establish the #factory_class before we proceed with the metadata.  See
      # https://github.com/samvera-labs/bulkrax/issues/702 for further details.
      #
      # tl;dr - if we don't have the right factory_class we might skip properties that are
      # specifically assigned to the factory class
      establish_factory_class
      add_metadata_from_record
      add_visibility
      add_rights_statement
      add_admin_set_id
      add_collections
      self.parsed_metadata['file'] = self.raw_metadata['file']

      add_local
      raise StandardError, "title is required" if self.parsed_metadata['title'].blank?
      self.parsed_metadata
    end

    def establish_factory_class
      model_field_names = parser.model_field_mappings

      each_candidate_metadata_node_name_and_content(elements: parser.model_field_mappings) do |name, content|
        next unless model_field_names.include?(name)
        add_metadata(name, content)
      end
    end

    def add_metadata_from_record
      each_candidate_metadata_node_name_and_content do |name, content|
        add_metadata(name, content)
      end
    end

    def each_candidate_metadata_node_name_and_content(elements: field_mapping_from_values_for_xml_element_names)
      elements.each do |name|
        # NOTE: the XML element name's case matters
        nodes = record.xpath("//*[name()='#{name}']")
        next if nodes.empty?

        nodes.each do |node|
          node.children.each do |content|
            next if content.to_s.blank?

            yield(name, content.to_s)
          end
        end
      end
    end

    # Returns the explicitly declared "from" key's value of each parser's element's value.  (Yes, I
    # would like a proper class for the thing I just tried to describe.)
    #
    # @return [Array<String>]
    #
    # @todo Additionally, we may want to revisit the XML parser fundamental logic; namely we only
    #       parse nodes that are explicitly declared with in the `from`.  This is a bit different
    #       than other parsers, in that they will make assumptions about each encountered column (in
    #       the case of CSV) or node (in the case of OAI).  tl;dr - Here there be dragons.
    def field_mapping_from_values_for_xml_element_names
      Bulkrax.field_mappings[self.importerexporter.parser_klass].map do |_k, v|
        v[:from]
      end.flatten.compact.uniq
    end

    # Included for potential downstream adopters
    alias xml_elements field_mapping_from_values_for_xml_element_names
    deprecation_deprecate xml_elements: "Use '#{self}#field_mapping_from_values_for_xml_element_names' instead"
  end
end
