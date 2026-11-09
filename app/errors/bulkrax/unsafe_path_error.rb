# frozen_string_literal: true

module Bulkrax
  # Raised by {Bulkrax::SafePath} when a path would escape its configured
  # root, whether that root is a ZIP extraction directory, an importer's
  # trusted workspace, or a configured filesystem-provider home.
  class UnsafePathError < StandardError; end
end
