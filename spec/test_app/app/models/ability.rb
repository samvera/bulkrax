# frozen_string_literal: true

class Ability
  include Hydra::Ability

  include Hyrax::Ability
  include Bulkrax::Ability
  self.ability_logic += [:everyone_can_create_curation_concerns, :bulkrax_default_abilities]

  # Define any customized permissions here.
  def custom_permissions
    # Limits deleting objects to a the admin user
    #
    # if current_user.admin?
    #   can [:destroy], ActiveFedora::Base
    # end

    # Limits creating new objects to a specific group
    #
    # if user_groups.include? 'special_group'
    #   can [:create], ActiveFedora::Base
    # end
  end

  # Override Bulkrax::Ability defaults for the test application.
  # All authenticated users who can create works may import and export.
  def can_import_works?
    can_create_any_work?
  end

  def can_export_works?
    can_create_any_work?
  end

  def can_create_any_work?
    true
  end
end
