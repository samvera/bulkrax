# frozen_string_literal: true

module Bulkrax
  # Raised when a zip cannot be safely or meaningfully extracted during
  # import. Covered scenarios include:
  #
  # - A single upload zip has no CSV at any level.
  # - A single upload zip has multiple CSVs at its shallowest level
  #   (primary CSV cannot be determined).
  # - A zip entry's name would escape the destination directory
  #   (Zip Slip: absolute paths, `..` traversal, etc.).
  #
  # Defined in its own file so Zeitwerk can autoload the constant by name
  # from any parser or job that raises or rescues it.
  class UnzipError < StandardError; end
end
