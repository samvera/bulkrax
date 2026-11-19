# frozen_string_literal: true

class User < ApplicationRecord
  def to_s
    email
  end
end
