# frozen_string_literal: true

require 'csv'

module Bulkrax
  # Raised when an import CSV cannot be parsed, most often because it was
  # saved in an encoding other than UTF-8. The message is written for the
  # person uploading the file.
  #
  # Subclasses CSV::MalformedCSVError so code that already rescues that
  # error keeps working.
  class CsvReadError < CSV::MalformedCSVError
    def initialize(message, line_number = nil)
      @user_message = message
      super
    end

    # MalformedCSVError appends " in line N." to its message; this message
    # already says where the problem is.
    def to_s
      @user_message
    end
  end
end
