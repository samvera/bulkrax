# frozen_string_literal: true

class Site < ApplicationRecord
  class << self

    def instance
      Site.create
      # return NilSite.instance if Account.global_tenant?
      # first_or_create do |site|
      #   site.available_works = Hyrax.config.registered_curation_concern_types
      # end
    end
  end

    def account
      "account"
    end
end
