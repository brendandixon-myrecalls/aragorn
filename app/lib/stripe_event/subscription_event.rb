module StripeEvent

  SUBSCRIPTION_EVENT_TYPES = %w(customer.subscription.deleted customer.subscription.updated)

  class SubscriptionEvent < BaseEvent

    def subscription_from_(event)
      event.data.object rescue nil
    end

    def call(event)
      return unless SUBSCRIPTION_EVENT_TYPES.include?(event.type)

      user = self.customer_to_user(event)
      return unless user.present?

      stripe_subscription = event.data.object rescue nil
      if stripe_subscription.blank?
        self.warn(event, "Event did not contain Stripe subscription")
        return
      end

      if user.synchronize_stripe!(stripe_subscription).blank?
        self.warn(event, "Failed up update Stripe subscription #{stripe_subscription.id} for User #{user.email}")
        return
      end

      self.info(event, "Deleted Stripe subscription #{stripe_subscription.id} for User #{user.email}")
      true
    end

  end

end
