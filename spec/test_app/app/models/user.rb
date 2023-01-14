# frozen_string_literal: true

class User < ApplicationRecord
  def self.batch_user; end

  def guest?
    false
  end

  def user_key
    ''
  end
end
