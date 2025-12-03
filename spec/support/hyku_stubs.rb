# frozen_string_literal: true

# Stub classes for Hyku-specific functionality when testing against non-Hyku apps
unless defined?(Site)
  class Site
    attr_accessor :id, :account_id

    def self.instance
      @instance ||= new(id: 1, account_id: 1)
    end

    def initialize(id: nil, account_id: nil)
      @id = id
      @account_id = account_id
    end

    def account
      @account ||= Account.new
    end
  end
end

unless defined?(Account)
  class Account
    attr_accessor :id

    def initialize(id: 1)
      @id = id
    end

    def name
      'test_account'
    end
  end
end
