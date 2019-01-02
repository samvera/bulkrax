module Bulkrax
  module Factories
    class WorkFactory < ObjectFactory
      include WithAssociatedCollection

      self.klass = Work
      # A way to identify objects that are not Hydra minted identifiers
      self.system_identifier_field = 'identifier'
    end
  end
end
