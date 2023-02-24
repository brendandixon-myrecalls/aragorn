class RecallAuthorizer < ApplicationAuthorizer

  class<<self

    def readable_by?(user)
      super
      user.acts_as_member?
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
    user.acts_as_worker? || (self.public_feed? && user.has_recall_subscription?(resource.publication_date))
  end

  def updatable_by?(user, options = {})
    super
    user.acts_as_worker?
  end

  def deletable_by?(user, options = {})
    super
    user.acts_as_worker?
  end

  protected

    def public_feed?
      !FeedConstants::NONPUBLIC_NAMES.include?(resource.feed_name)
    end

end
