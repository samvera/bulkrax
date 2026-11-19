# frozen_string_literal: true

class User < ApplicationRecord
  def self.batch_user; end

  def self.find_by_user_key(key)
    find_by(email: key)
  end

  def guest?
    false
  end

  def user_key
    email
  end
end
