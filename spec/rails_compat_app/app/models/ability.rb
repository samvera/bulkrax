# frozen_string_literal: true

# The host app supplies Ability. This one belongs to an administrator, who may
# import and export everything.
class Ability
  include Bulkrax::AbilityBehavior

  def initialize(user)
    @user = user
  end

  def authorize!(*)
    true
  end

  def can_admin_importers?
    true
  end

  def can_admin_exporters?
    true
  end
end
