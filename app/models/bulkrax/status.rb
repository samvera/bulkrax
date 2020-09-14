# frozen_string_literal: true

module Bulkrax
  class Status < ApplicationRecord
    belongs_to :statusable, polymorphic: true
    belongs_to :runnable, polymorphic: true
  end
end
