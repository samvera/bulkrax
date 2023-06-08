# frozen_string_literal: true

config = YAML.load(ERB.new(IO.read(Rails.root + 'config' + 'redis.yml')).result)[Rails.env].with_indifferent_access
sentinels = config[:sentinel] && config[:sentinel][:host].present? ? { sentinels: [config[:sentinel]] } : {}
redis_config = config.except(:sentinel).merge(thread_safe: true).merge(sentinels)
require 'redis'
Redis.current = begin
                  Redis.new(redis_config)
                rescue
                  nil
                end
