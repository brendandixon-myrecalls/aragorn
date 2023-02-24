module Emailable
  extend ActiveSupport::Concern

  EMAIL_FIELDS = [:email]

  included do
    validates_email :email
    validates_length_of :email, within: 6..255, unless: lambda{|em| em.errors.has_key?(:email)}
    validates_uniqueness_of :email, unless: lambda{|em| em.persisted? || em.errors.has_key?(:email)}

    if self.respond_to?(:scope)
      scope :in_email_order, lambda{|asc=false| self.order_by(email: asc ? 1 : -1)}
      scope :with_email, lambda{|email| self.where(email: (email || '').downcase)}
    end
  end

end
