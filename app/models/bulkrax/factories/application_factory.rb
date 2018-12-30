module Bulkrax
  module Factories
    class ApplicationFactory
      extend ActiveSupport::Autoload

      eager_autoload do
        autoload :CollectionFactory
        autoload :WorkFactory if defined?(Work)
        autoload :ImageFactory if defined?(Image)
        autoload :ObjectFactory
        autoload :WithAssociatedCollection
      end

      # @param [#to_s] First (Xxx) portion of an "XxxFactory" constant
      def self.for(model_name)
        const_get "Bulkrax::Factories::#{model_name}Factory"
      end
    end
  end
end
