# frozen_string_literal: true

module Bulkrax
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
