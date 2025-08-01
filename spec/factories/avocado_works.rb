# frozen_string_literal: true

# In order to use this factory, you need to add this block to your spec file:
# around do |spec|
#   class ::Avocado < Work
#     property :bulkrax_identifier, predicate: ::RDF::URI("https://hykucommons.org/terms/bulkrax_identifier"), multiple: false
#   end
#   spec.run
#   Object.send(:remove_const, :Avocado)
# end

FactoryBot.define do
  factory :avocado_work, class: 'Avocado' do
    id { 'work_id' }
    title { ['A Work'] }
    bulkrax_identifier { "BU_Collegian-19481124" }
  end

  factory :another_avocado_work, class: 'Avocado' do
    id { 'another_work_id' }
    title { ['Another Work'] }
    bulkrax_identifier { "BU_Collegian-123" }
  end
end
