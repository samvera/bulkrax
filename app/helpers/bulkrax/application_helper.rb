# frozen_string_literal: true

module Bulkrax
  module ApplicationHelper
    include Hyrax::HyraxHelperBehavior

    def coderay(value, opts)
      CodeRay
        .scan(value, :ruby)
        .html(opts)
        .html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
