if defined?(Work)
  module Bulkrax
    class WorkFactory < ObjectFactory
      include WithAssociatedCollection

      self.klass = Work
      # A way to identify objects that are not Hydra minted identifiers
      self.system_identifier_field = Bulkrax.system_identifier_field
    end
  end
end
