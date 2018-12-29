module Bulkrax
  module Entries
    class ApplicationEntry

      def build
        # attributes, files_dir = nil, files = [], user = nil
        Bulkrax::Factories::ApplicationFactory.for(entry_class).new(all_attrs, nil, [], user).run
      end

    end
  end
end
