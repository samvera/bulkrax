# frozen_string_literal: true

module Bulkrax
  # Raised by {Bulkrax::CloudSourceValidator} when a cloud-file source
  # (the `url` a user selected via browse-everything, or supplied directly
  # in importer params) can't be safely downloaded: a scheme other than
  # `file`/`http`/`https`, a `file:` source outside the configured
  # filesystem-provider root, or an HTTP(S) source that resolves to a
  # private, loopback, or link-local/metadata address.
  class UnsafeCloudSourceError < StandardError; end
end
