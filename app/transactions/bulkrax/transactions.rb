# frozen_string_literal: true
require 'bulkrax/container'

module Bulkrax
  ##
  # This is a parent module for DRY Transaction classes handling Bulkrax
  # processes. Especially: transactions and steps for creating, updating, and
  # destroying PCDM Objects are located here.
  #
  # @since 2.4.0
  #
  # @example
  #   Bulkrax::Transaction::Container['transaction_name'].call(:input)
  #
  # @see https://dry-rb.org/gems/dry-transaction/
  module Transactions
  end
end
