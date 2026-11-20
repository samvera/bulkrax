# frozen_string_literal: true

module Bulkrax
  # Locks a record the way Hyrax::Lockable does. Without Hyrax there is no lock
  # manager, so the block runs unlocked.
  module Lockable
    class RecordLockedError < StandardError; end

    # Up to 30 seconds is added so jobs waiting on one record don't all retry together
    def self.retry_wait(attempt)
      (2**(attempt - 1)).minutes + rand(30).seconds
    end

    def acquire_lock_for(key, &block)
      return yield unless Bulkrax.hyrax_loaded?

      begin
        lock_manager.lock(key, &block)
      rescue Hyrax::LockManager::UnableToAcquireLockError
        raise RecordLockedError, "Timed out waiting for the lock on #{key}; another job was still updating it"
      end
    end

    def conditionally_acquire_lock_for(key, &block)
      return yield unless Bulkrax.use_locking?

      acquire_lock_for(key, &block)
    end

    private

    def lock_manager
      @lock_manager ||= Hyrax::LockManager.new(Hyrax.config.lock_time_to_live, Hyrax.config.lock_retry_count, Hyrax.config.lock_retry_delay)
    end
  end
end
