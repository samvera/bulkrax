# frozen_string_literal: true

module Bulkrax
  class ImportJob < ApplicationJob
    queue_as :import

 end
end
