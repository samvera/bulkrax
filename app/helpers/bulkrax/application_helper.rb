# frozen_string_literal: true

require 'coderay'

module Bulkrax
  module ApplicationHelper
    include Hyrax::HyraxHelperBehavior

    def coderay(value, opts)
      CodeRay
        .scan(value, :ruby)
        .html(opts)
        .html_safe
    end
  end
end
