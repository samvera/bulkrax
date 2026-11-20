# frozen_string_literal: true

module Bulkrax
  # Locks a record the way Hyrax::Lockable does. Without Hyrax there is no lock
  # manager, so the block runs unlocked.
  module Lockable
    def acquire_lock_for(key, &block)
      return yield unless Bulkrax.hyrax_loaded?

      lock_manager.lock(key, &block)
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
