# frozen_string_literal: true
require 'coderay'

module Bulkrax
  module ApplicationHelper
    include ::Hyrax::HyraxHelperBehavior if defined?(::Hyrax)

    def coderay(value, opts)
      CodeRay
        .scan(value, :ruby)
        .html(opts)
        .html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
