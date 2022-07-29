# frozen_string_literal: true

class Site < ApplicationRecord
  class << self

    def instance
      Site.create
    end
  end

    def account
      "account"
    end
end
