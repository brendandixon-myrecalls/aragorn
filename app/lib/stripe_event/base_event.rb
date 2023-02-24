module StripeEvent

  class BaseEvent

    def initialize(logger)
      @logger = logger
    end

    def logger
      @logger
    end

    def error(event, msg)
      self.logger.error "Stripe Event #{event.id} #{event.type} - #{msg}"
    end

    def info(event, msg)
      self.logger.info "Stripe Event #{event.id} #{event.type} - #{msg}"
    end

    def warn(event, msg)
      self.logger.warn "Stripe Event #{event.id} #{event.type} - #{msg}"
    end

    def customer_to_user(event)
      customer = event.data.object.customer rescue nil
      user = User.with_customer(customer).first rescue nil
      self.warn(event, "Customer #{customer} not found") if user.blank?
      user
    end

  end

end
