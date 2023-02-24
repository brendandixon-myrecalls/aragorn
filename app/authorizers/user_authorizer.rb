class UserAuthorizer < ApplicationAuthorizer

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
    self.for_self?(user) || user.acts_as_worker?
  end

  def updatable_by?(user, options = {})
    super
    self.for_self?(user) || user.acts_as_worker?
  end

  def deletable_by?(user, options = {})
    super
    (user.acts_as_worker?) && !self.for_self?(user)
  end

end
