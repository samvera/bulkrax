FactoryBot.define do
  factory :object_factory, class: 'Bulkrax::ObjectFactory' do
    skip_create
    
    transient do
      attrs { {} }
    end
    
    source_identifier_value { 'source_identifier' }
    work_identifier { :source }
    work_identifier_search_field { 'source_sim' }
    
    initialize_with do
      Bulkrax::ObjectFactory.new(
        attributes: attrs,
        source_identifier_value: source_identifier_value,
        work_identifier: work_identifier,
        work_identifier_search_field: work_identifier_search_field
      )
    end
  end

  factory :valkyrie_object_factory, class: 'Bulkrax::ValkyrieObjectFactory' do
    skip_create
    
    transient do
      attrs { {} }
    end
    
    source_identifier_value { 'source_identifier' }
    work_identifier { :source }
    work_identifier_search_field { 'bulkrax_identifier_sim' }
    
    initialize_with do
      Bulkrax::ValkyrieObjectFactory.new(
        attributes: attrs,
        source_identifier_value: source_identifier_value,
        work_identifier: work_identifier,
        work_identifier_search_field: work_identifier_search_field
      )
    end
  end
end
