# frozen_string_literal: true

module Bulkrax
  # Raised when a file set queued to a work is already in another one. A file set belongs to one work.
  class FileSetInAnotherWorkError < StandardError; end
end
