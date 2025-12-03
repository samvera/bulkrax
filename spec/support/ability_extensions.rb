# frozen_string_literal: true

# Add Bulkrax ability methods to the Dassie Ability class
# Normally these would be added by the Bulkrax install generator
Ability.class_eval do
  def can_import_works?
    true  # Allow in tests - in production this would check can_create_any_work?
  end

  def can_export_works?
    true  # Allow in tests - in production this would check can_create_any_work?
  end
end
