class VehicleRecallAuthorizer < ApplicationAuthorizer

  # Note:
  # - Members have access to VehicleRecalls *through* the Vehicles
  #   attached to their Subscriptions.
  #   Only workers can directly access VehicleRecalls.

  class<<self

    def readable_by?(user)
      super
      user.acts_as_worker?
    end

    def updatable_by?(user)
      super
      user.acts_as_worker?
    end

  end

  def creatable_by?(user, options = {})
    super
    user.acts_as_worker?
  end

  def readable_by?(user, options = {})
    super
    user.acts_as_worker?
  end

  def updatable_by?(user, options = {})
    super
    user.acts_as_worker?
  end

  def deletable_by?(user, options = {})
    super
    user.acts_as_worker?
  end

end
