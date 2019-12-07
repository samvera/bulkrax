require 'rdf'
module Bulkrax
  class RdfEntry < Entry
    serialize :raw_metadata, JSON

    def self.read_data(path)
      RDF::Reader.open(path)
    end

    def self.fields_from_data(data)
      data.predicates.map(&:to_s)
    end

    def self.data_for_entry(data, path = nil, index = 0)
      reader = data
      format = reader.class.format.to_sym
      data = RDF::Writer.for(format).buffer do |writer|
        reader.each_statement do |statement|
          writer << statement
        end
      end
      return { source_identifier: reader.subjects.first.to_s, format: format, data: data, file: record_file_paths(path) }
    end

    # Return all files, including metadata and bagit files
    def self.record_file_paths(path)
      return [] if path.nil?
      Dir.glob("#{File.dirname(path)}/**/*").reject { |f| File.file?(f) == false }
    end

    def record
      @record ||= RDF::Reader.for(self.raw_metadata['format'].to_sym).new(self.raw_metadata['data'])
    end

    def build_metadata
      raise StandardError, 'Record not found' if record.nil?
      raise StandardError, 'Missing source identifier' if self.raw_metadata['source_identifier'].blank?

      self.parsed_metadata = {}
      self.parsed_metadata[Bulkrax.system_identifier_field] = [self.raw_metadata['source_identifier']]

      record.each_statement do |statement|
        # Only process the subject for our record (in case other data is in the file)
        next unless statement.subject.to_s == self.raw_metadata['source_identifier']
        add_metadata(statement.predicate.to_s, statement.object.to_s)
      end
      add_visibility
      add_rights_statement
      add_collections
      add_local
      self.parsed_metadata['file'] = self.raw_metadata['file']

      self.parsed_metadata
    end
  end
end
