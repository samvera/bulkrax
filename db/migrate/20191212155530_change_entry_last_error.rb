class ChangeEntryLastError < ActiveRecord::Migration[5.1]

  class Bulkrax::Entry < ActiveRecord::Base
  end

  def change
    errors = {}
    last_error = Bulkrax::Entry.arel_table[:last_error]
    Bulkrax::Entry.where(last_error.matches("%\n\n%")).each do | entry |
      old_errors = entry.last_error.split("\n\n") unless entry.last_error.nil?
      errors[entry.id] = { 
        'error_class' => 'unknown', 
        'error_message' => old_errors.first,
        'error_trace' => old_errors.last
      }
      entry.update_attribute(:last_error, nil)
    end

    Bulkrax::Entry.class_eval do
      serialize :last_error, JSON
    end

    errors.each_pair do | entry, value |
      Bulkrax::Entry.find(entry).update_attribute(:last_error, value)
    end 
  end

end
