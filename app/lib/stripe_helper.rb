class StripeHelper

  DELAY_IN_SECONDS = 0.5
  MAX_ATTEMPTS = 3

  unless Rails.env.production?
    # See https://stripe.com/docs/testing
    CARDS = {
      valid: '4242424242424242',

      cvc_check_failed: '4000000000000101',
      incorrect_cvc: '4000000000000127',
      incorrect_luhn: '4242424242424241',

      declined: '4000000000000002',
      expired: '4000000000000069',
      failed: '4000000000000341',
      insufficient_funds: '4000000000009995',
      processing_error: '4000000000000119',

      fraudulent: '4100000000000019',
      lost_card: '4000000000009987',
      stolen_card: '4000000000009979',

      address_failure: '4000000000000028',
      zip_failure: '4000000000000036',

      disputed_fraud: '4000000000000259',
      disputed_not_received: '4000000000002685',
      disputed_inquiry: '4000000000001976',
      early_fraud_warning: '4000000000005423',
    }
  end

  class<<self

    def logger
      Rails.logger
    end

    def delete_customer(user)
      return if user.customer_id.blank?

      opts = generate_idempotent_options
      customer = invoke_stripe(:delete_customer) { Stripe::Customer.delete(user.customer_id, {}, opts) }
      user.customer_id = nil
      user.subscriptions = []
      user.save!
    end

    def ensure_customer(user, token=nil)
      return true if user.customer_id.present? && token.blank?

      user.with_lock(reload: true) do
        raise BadRequestError.new('No token provided for new customer') if user.customer_id.blank? && token.blank?

        opts = generate_idempotent_options
        params = { source: token }

        if user.customer_id.blank?
          params[:email] = user.email
          customer = invoke_stripe(:create_customer) { Stripe::Customer.create(params, opts) }
          user.customer_id = customer.id
          user.save!
        else
          invoke_stripe(:update_customer_card) { Stripe::Customer.update(user.customer_id, params, opts) }
        end
        true
      end
    rescue Mongoid::Locker::Errors::MongoidLockerError
      logger.error("Failed to aquire lock while ensuring Stripe customer for User #{user.email}")
      false
    end

    def update_customer(user)
      return unless user.customer_id.present?

      opts = generate_idempotent_options
      invoke_stripe(:update_customer) do 
        customer = Stripe::Customer.retrieve(user.customer_id, opts)
        customer.email = user.email
        customer.save
      end
    end

    def create_subscription(user, plan_id, coupon=nil, token=nil)
      raise BadRequestError.new("Failed to create or update Stripe customer for User #{user.email}") unless ensure_customer(user, token)

      if !coupon.is_a?(Coupon) && coupon.present?
        coupon = Coupon.from_id(coupon)
        raise BadRequestError.new('The coupon is not valid.') unless coupon.present?
      end
 
      plan = Plan.from_id(plan_id)
      raise BadRequestError.new("The plan #{plan_id} is not recognized subscription plan.") unless plan.present?
      raise BadRequestError.new('User already has a Recalls subscription') unless user.can_subscribe_to?(plan)

      opts = generate_idempotent_options
      params = { customer: user.customer_id, items: [{ plan: plan.id }]}
      params[:coupon] = coupon.id if coupon.present?

      stripe_subscription = invoke_stripe(:create_subscription) { Stripe::Subscription.create(params, opts) }
      unless stripe_subscription.status == 'active'
        raise BadRequestError.new('Failed to create an active subscription. Please try again later.')
      end

      subscription = user.synchronize_stripe!(stripe_subscription)
      raise BadRequestError.new('Failed to create user subscription. Please try again later.') unless subscription.present?

      subscription
    end

    def cancel_subscription(user, stripe_id, at_period_end=true)
      opts = generate_idempotent_options
      params = {
        cancel_at: at_period_end ? nil : Time.now,
        cancel_at_period_end: at_period_end
      }
      stripe_subscription = invoke_stripe(:cancel_subscription) { Stripe::Subscription.update(stripe_id, params, opts) }

      subscription = user.synchronize_stripe!(stripe_subscription)
      raise BadRequestError.new('Failed to cancel user subscription. Please try again later.') unless subscription.present?

      subscription
    end

    def retrieve_subscription(stripe_id)
      opts = generate_idempotent_options
      invoke_stripe(:retrieve_subscription) { Stripe::Subscription.retrieve(stripe_id, opts) }
    end

    def coupons
      @@coupons ||= begin
        opts = generate_idempotent_options
        params = {}
        list = invoke_stripe(:coupons) { Stripe::Coupon.list(params, opts) }
        list.data || []
      end
    end

    def plans
      @@plans ||= begin
        opts = generate_idempotent_options
        params = {}
        list = invoke_stripe(:plans) { Stripe::Plan.list(params, opts) }
        list.data || []
      end
    end

    unless Rails.env.production?
      def create_token(card_type=:valid)
        invoke_stripe(:create_token) { Stripe::Token.create({
          card: {
            number: CARDS[card_type],
            exp_month: 9,
            exp_year: 2020,
            cvc: '314',
          }
        })}
      end
    end

    def invoke_stripe(tag, &block)
      attempt = 0

      while true
        begin
          return yield block
        rescue Stripe::RateLimitError, Stripe::APIConnectionError => e
          attempt += 1
          raise e if attempt >= MAX_ATTEMPTS
          logger.warn "Stripe Error: Connection Issue Attempt[#{attempt}] Tag[#{tag}] Detail[#{e}]"
          Kernel.sleep(DELAY_IN_SECONDS * attempt)
        end
      end

      rescue Stripe::CardError => e
        detail = extract_detail(e)
        decline_code = detail[:decline_code].present? ? " #{detail[:decline_code]}" : ''
        message = e.message || (detail[:message].present? ? " #{detail[:message]}" : '')

        raise BadRequestError.new("Your card was not accepted. #{message.present? ? message : decline_code}")
      
      rescue Stripe::RateLimitError, Stripe::APIConnectionError => e
        logger.error "Stripe Error: Unable to complete request after #{MAX_ATTEMPTS} attempts - #{tag} #{e}"
        raise BadRequestError.new('Unable to complete the request. Please try again later.')
      
      rescue Stripe::InvalidRequestError => e
        detail = extract_detail(e)
        message = detail[:message] || ''
        logger.info "Stripe Error: Invalid Request Tag[#{tag}] Detail[#{message}]"
        raise BadRequestError.new('Unable to complete the request. Please try again.')
      
      rescue Stripe::AuthenticationError => e
        logger.error "Stripe Error: API Key Invalid Tag[#{tag}] Detail[#{e}]"
        raise BadRequestError.new('Unable to complete the request. Please try again later.')

      rescue Stripe::StripeError, StandardError => e
        logger.error "Stripe Error: Tag[#{tag}] Detail[#{e}]"
        raise BadRequestError.new('Unable to complete the request. Please try again later.')
    end

    def extract_detail(e)
      (e.json_body || {})[:error] || {}
    end

    def generate_idempotent_options
      { idempotency_key: SecureRandom.uuid }
    end

  end

end
