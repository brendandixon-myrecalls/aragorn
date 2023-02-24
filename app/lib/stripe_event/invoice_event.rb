module StripeEvent

  INVOICE_EVENT_TYPES = %w(invoice.payment_failed invoice.payment_succeeded)

  class InvoiceEvent < BaseEvent

    def call(event)
      return unless INVOICE_EVENT_TYPES.include?(event.type)

      user = self.customer_to_user(event)
      return unless user.present?

      plan = self.invoice_plan(event)
      plan = Plan.from_id(plan)
      return unless plan.present?

      subscription_id = self.invoice_subscription(event)

      stripe_subscription = StripeHelper.retrieve_subscription(subscription_id) rescue nil
      if stripe_subscription.blank?
        self.warn(event, "Unable to retrieve Stripe subscription #{subscription_id} for User #{user.email}")
        return
      end

      if user.synchronize_stripe!(stripe_subscription).blank?
        self.warn(event, "Failed to update Stripe subscription #{stripe_subscription.id} to status #{stripe_subscription.status} for User #{user.email}")
        return
      end

      self.info(event, "Updated Stripe subscription #{stripe_subscription.id} to status #{stripe_subscription.status} for User #{user.email}")
      true
    end

    def invoice_period(event)
      period = event.data.object.lines.data.first.period rescue {}
      return period if period.blank?
      { start: Time.at(period[:start]), end: Time.at(period[:end]) }
    end

    def invoice_plan(event)
      event.data.object.lines.data.first.plan.id rescue nil
    end

    def invoice_subscription(event)
      event.data.object.subscription rescue nil
    end

  end

end
