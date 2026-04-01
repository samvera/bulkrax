# frozen_string_literal: true

module Bulkrax
  module CsvRow
    ##
    # Detects circular parent-child relationships in the CSV.
    # A circular reference occurs when following the parent chain from any record
    # eventually leads back to itself (e.g. A→B→C→A).
    #
    # The validator builds a directed graph (child → parents) from all records on
    # first invocation and caches the set of all record ids involved in any cycle.
    # Subsequent per-row calls simply check membership in that set.
    #
    # Requires context key:
    #   :relationship_graph  – Hash { source_identifier => [parent_ids] } built by
    #                          run_row_validators before iterating rows.
    module CircularReference
      def self.call(record, row_index, context)
        cycle_ids = context[:circular_reference_ids] ||= detect_cycle_ids(context[:relationship_graph] || {})
        return unless cycle_ids.include?(record[:source_identifier])

        context[:errors] << {
          row: row_index,
          source_identifier: record[:source_identifier],
          severity: 'error',
          category: 'circular_reference',
          column: 'parents',
          value: record[:source_identifier],
          message: I18n.t('bulkrax.importer.guided_import.validation.circular_reference_validator.errors.message',
                          value: record[:source_identifier]),
          suggestion: I18n.t('bulkrax.importer.guided_import.validation.circular_reference_validator.errors.suggestion')
        }
      end

      # Returns the set of all source identifiers that participate in at least one cycle.
      # Uses recursive DFS with a per-branch ancestry set to detect back-edges.
      def self.detect_cycle_ids(graph)
        all_nodes = graph.keys.to_set | graph.values.flatten.to_set
        visited   = Set.new
        cycle_ids = Set.new

        all_nodes.each do |node|
          next if visited.include?(node)
          dfs(node, graph, visited, [], cycle_ids)
        end

        cycle_ids
      end
      private_class_method :detect_cycle_ids

      def self.dfs(node, graph, visited, ancestors, cycle_ids) # rubocop:disable Metrics/MethodLength
        visited.add(node)
        ancestors.push(node)

        (graph[node] || []).each do |neighbor|
          if ancestors.include?(neighbor)
            # Back-edge found: mark every node in the cycle path
            cycle_start = ancestors.index(neighbor)
            ancestors[cycle_start..].each { |n| cycle_ids.add(n) }
            cycle_ids.add(neighbor)
          elsif !visited.include?(neighbor)
            dfs(neighbor, graph, visited, ancestors, cycle_ids)
          end
        end

        ancestors.pop
      end
      private_class_method :dfs
    end
  end
end
