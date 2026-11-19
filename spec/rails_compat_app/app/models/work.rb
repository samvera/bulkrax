# frozen_string_literal: true

# Stands in for a non-Hyrax app's repository model, such as an ActiveFedora
# work, with the query methods (find, exists?, where) that model offers.
class Work < ApplicationRecord
  # Like ActiveFedora's ordered_members: << appends and returns the list.
  class OrderedMembers
    def initialize(work)
      @work = work
    end

    def <<(child)
      @work.member_ids = Array(@work.member_ids) + [child.id]
      self
    end

    def to_a
      Array(@work.member_ids).map { |id| Work.find(id) }
    end
  end

  def self.properties
    {
      'bulkrax_identifier' => { 'multiple' => false },
      'title' => { 'multiple' => false },
      'creator' => { 'multiple' => true }
    }
  end

  # Bulkrax asks method_defined? to see which fields a model supports.
  # ActiveFedora defines property accessors when the class loads, where
  # ActiveRecord would wait for the first instance.
  define_attribute_methods

  # ActiveFedora's list of the record's model names
  def has_model
    [self.class.name]
  end

  def ordered_members
    OrderedMembers.new(self)
  end

  def work?
    true
  end

  def collection?
    false
  end
end
