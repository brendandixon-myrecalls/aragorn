class SubscriptionAuthorizer < ApplicationAuthorizer

  # Note:
  # - Members have full subscription / vehicle access (except deletion)
  # - The controller limits what subscriptions / vehicles to those owned by the current user (except for workers)

  class<<self

    # Note:
    # - This provides authorization ONLY for the index collection action
    def readable_by?(user)
      super
      user.acts_as_member?
    end

  end

  def creatable_by?(user, options = {})
    super
    user.acts_as_member?
  end

  def readable_by?(user, options = {})
    super
    user.acts_as_member?
  end

  def updatable_by?(user, options = {})
    super
    user.acts_as_member?
  end

  def deletable_by?(user, options = {})
    super
    user.acts_as_worker?
  end

end
