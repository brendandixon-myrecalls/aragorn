# Other authorizers should subclass this one
class ApplicationAuthorizer < Authority::Authorizer

  class <<self

    # Any class method from Authority::Authorizer that isn't overridden
    # will call its authorizer's default method.
    #
    # @param [Symbol] adjective; example: `:creatable`
    # @param [Object] user - whatever represents the current user in your app
    # @return [Boolean]
    def default(adjective, user)
      # 'Whitelist' strategy for security: anything not explicitly allowed is
      # considered forbidden.
      false
    end

  end

  def creatable_by?(member, options = {})
    false
  end

  def readable_by?(member, options = {})
    false
  end

  def updatable_by?(member, options = {})
    false
  end

  def deletable_by?(member, options = {})
    false
  end

  protected

    def for_self?(user)
      owner = resource
      while owner._parent.present? do owner = owner._parent end
      user.id == (owner.is_a?(User) ? owner.id : owner.user_id)
    end

end
