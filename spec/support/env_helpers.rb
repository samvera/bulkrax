# frozen_string_literal: true

module EnvHelpers
  def stub_env(name, value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with(name).and_return(value)
  end
end

RSpec.configure do |config|
  config.include EnvHelpers
end
