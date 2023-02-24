require 'rails_helper'

describe 'StripeHelper', type: :lib do

  before :all do
    @faux = [{a: 1}, {b: 2}]
  end

  describe 'Invoking Stripe' do

    it 'returns invokes the block' do
      invoked = false
      StripeHelper.invoke_stripe(:test) { invoked = true }
      expect(invoked).to be true
    end

    it 'returns the results from the block' do
      results = StripeHelper.invoke_stripe(:test) { @faux }
      expect(results).to eq(@faux)
    end

    it 'retries rate limiting errors' do
      attempts = 0
      allow(Kernel).to receive(:sleep).and_return(0)
      StripeHelper.invoke_stripe(:test) do
        attempts += 1
        raise Stripe::RateLimitError.new if attempts < StripeHelper::MAX_ATTEMPTS
      end
      expect(attempts).to eq(StripeHelper::MAX_ATTEMPTS)
    end

    it 'retries rate limiting errors up to a maximum' do
        attempts = 0
        allow(Kernel).to receive(:sleep).and_return(0)
        expect {
          StripeHelper.invoke_stripe(:test) do
            attempts += 1
            raise Stripe::RateLimitError.new
          end
        }.to raise_error(BadRequestError)
        expect(attempts).to be <= StripeHelper::MAX_ATTEMPTS
    end

    it 'logs an error if rate limiting errors reach their maximum' do
        allow(Kernel).to receive(:sleep).and_return(0)
        expect(Rails.logger).to receive(:error)
        expect {
          StripeHelper.invoke_stripe(:test) do
            raise Stripe::RateLimitError.new
          end
        }.to raise_error(BadRequestError)
    end

    it 'retries connection errors' do
      attempts = 0
      allow(Kernel).to receive(:sleep).and_return(0)
      StripeHelper.invoke_stripe(:test) do
        attempts += 1
        raise Stripe::APIConnectionError.new if attempts < StripeHelper::MAX_ATTEMPTS
      end
      expect(attempts).to eq(StripeHelper::MAX_ATTEMPTS)
    end

    it 'retries connection errors up to a maximum' do
        attempts = 0
        allow(Kernel).to receive(:sleep).and_return(0)
        expect {
          StripeHelper.invoke_stripe(:test) do
            attempts += 1
            raise Stripe::APIConnectionError.new
          end
        }.to raise_error(BadRequestError)
        expect(attempts).to be <= StripeHelper::MAX_ATTEMPTS
    end

    it 'logs an error if rate limiting errors reach their maximum' do
        allow(Kernel).to receive(:sleep).and_return(0)
        expect(Rails.logger).to receive(:error)
        expect {
          StripeHelper.invoke_stripe(:test) do
            raise Stripe::APIConnectionError.new
          end
        }.to raise_error(BadRequestError)
    end

    it 'retries only rate limiting and connection errors' do
      [
        Stripe::CardError.new('message', 'param'),
        Stripe::InvalidRequestError.new('message', 'param'),
        Stripe::AuthenticationError.new,
        Stripe::StripeError.new,
        StandardError.new
      ].each do |e|
        attempts = 0
        allow(Kernel).to receive(:sleep).and_return(0)
        expect {
          StripeHelper.invoke_stripe(:test) do
            attempts += 1
            raise e unless attempts >= StripeHelper::MAX_ATTEMPTS
          end
        }.to raise_error(BadRequestError)
        expect(attempts).to eq(1)
      end
    end

    it 'returns a helpful message for card errors' do
      allow(Kernel).to receive(:sleep).and_return(0)
      expect {
        StripeHelper.invoke_stripe(:test) do
          raise Stripe::CardError.new('message', 'param')
        end
      }.to raise_error(BadRequestError, /.*message.*/)
    end

    it 'does not log card errors' do
      expect(Rails.logger).to_not receive(:error)
      expect(Rails.logger).to_not receive(:info)
      expect(Rails.logger).to_not receive(:warn)
      allow(Kernel).to receive(:sleep).and_return(0)
      expect {
        StripeHelper.invoke_stripe(:test) do
          raise Stripe::CardError.new('message', 'param')
        end
      }.to raise_error(BadRequestError)
    end

    it 'logs errors for authentication failures' do
      expect(Rails.logger).to receive(:error)
      expect {
        StripeHelper.invoke_stripe(:test) do
          raise Stripe::AuthenticationError.new
        end
      }.to raise_error(BadRequestError)
    end

    it 'logs invalid requests' do
      expect(Rails.logger).to receive(:info)
      expect {
        StripeHelper.invoke_stripe(:test) do
          raise Stripe::InvalidRequestError.new('message', 'param')
        end
      }.to raise_error(BadRequestError)
    end

    it 'logs errors for all other errors' do
      [
        Stripe::StripeError.new,
        StandardError.new
      ].each do |e|
        expect(Rails.logger).to receive(:error)
        allow(Kernel).to receive(:sleep).and_return(0)
        expect {
          StripeHelper.invoke_stripe(:test) do
            raise e unless attempts >= StripeHelper::MAX_ATTEMPTS
          end
        }.to raise_error(BadRequestError)
      end
    end

  end

  describe 'Coupons' do

    it 'returns the coupons' do
      coupons = StripeHelper.coupons
      expect(coupons).to be_an(Array)
      expect(coupons.length).to be > 0
      coupons.each {|c| expect(c).to be_a(Stripe::Coupon) }
    end

  end

  describe 'Customers' do

    before :example do
      @user = create(:user, count_subscriptions: 0)
      @customer = Stripe::Customer.construct_from(load_stripe('customer.json'))
      @destroyed = load_stripe('customer_deleted.json')
    end

    after :example do
      User.unlock_all
      User.destroy_all
    end

    it 'destroys a customer if present' do
      expect(@user.customer_id).to be_blank

      expect(Stripe::Customer).to receive(:create).and_return(@customer)

      StripeHelper.ensure_customer(@user, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')

      expect(Stripe::Customer).to receive(:delete).and_return(@destroyed)
      StripeHelper.delete_customer(@user)
      expect(@user.customer_id).to be_blank
    end

    it 'does not invoke Stripe to destroy a customer if no customer is present' do
      expect(@user.customer_id).to be_blank

      expect(Stripe::Customer).to_not receive(:delete)

      StripeHelper.delete_customer(@user)
      expect(@user.customer_id).to be_blank
    end

    it 'ensures the user has a customer account' do
      expect(@user.customer_id).to be_blank

      expect(Stripe::Customer).to receive(:create).and_return(@customer)

      StripeHelper.ensure_customer(@user, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
    end

    it 'returns true if successful' do
      expect(@user.customer_id).to be_blank

      expect(Stripe::Customer).to receive(:create).and_return(@customer)

      expect(StripeHelper.ensure_customer(@user, 'faux_token')).to be true
      expect(@user.customer_id).to eq('cus_customer')
    end

    it 'returns false if unable to acquire the User lock' do
      expect(@user.customer_id).to be_blank

      expect(@user).to receive(:with_lock).and_raise(Mongoid::Locker::Errors::DocumentCouldNotGetLock.new(User, @user.id))
      expect(Stripe::Customer).to_not receive(:create)

      expect(StripeHelper.ensure_customer(@user, 'faux_token')).to be false
    end

    it 'does not create a new customer if the user already has a customer account' do
      @user.customer_id = 'cus_customer'
      @user.save!

      expect(Stripe::Customer).to_not receive(:create)

      StripeHelper.ensure_customer(@user)
      expect(@user.customer_id).to eq('cus_customer')
    end

    it 'does update the customer if a token is provided' do
      @user.customer_id = 'cus_customer'
      @user.save!

      expect(Stripe::Customer).to receive(:update)

      StripeHelper.ensure_customer(@user, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
    end

    it 'raises an error for new customers without a token' do
      expect { StripeHelper.ensure_customer(@user) }.to raise_error(BadRequestError)
    end

    it 'updates the email on the customer account' do
      @user.email = 'new_email@nomail.com'
      @user.customer_id = @customer.id

      expect(Stripe::Customer).to receive(:retrieve).and_return(@customer)
      expect(@customer).to receive(:save).and_return({})
      StripeHelper.update_customer(@user)
      expect(@customer.email).to eq('new_email@nomail.com')
    end

  end

  describe 'Plans' do

    it 'returns the plans' do
      plans = StripeHelper.plans
      expect(plans).to be_an(Array)
      expect(plans.length).to be > 0
      plans.each {|c| expect(c).to be_a(Stripe::Plan) }
    end

  end

  describe 'Subscriptions' do

    before :example do
      @coupon = Coupon.all.first
      @customer = Stripe::Customer.construct_from(load_stripe('customer.json'))
      @subscription = Stripe::Subscription.construct_from(load_stripe('all_subscription.json'))
      @ended = Stripe::Subscription.construct_from(load_stripe('ended_subscription.json'))

      @user = create(:user, count_subscriptions: 0)
    end

    after :example do
      User.destroy_all
    end

    it 'returns the subscription if successful' do
      expect(@user.customer_id).to be_blank

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to receive(:create).and_return(@subscription)

      s = StripeHelper.create_subscription(@user, Plan.yearly_all, nil, 'faux_token')
      expect(s).to be_is_a(Subscription)
      expect(@user.customer_id).to eq('cus_customer')
    end

    it 'returns nil if unable to acquire the User lock' do
      expect(@user.customer_id).to be_blank
      @user.customer_id = 'cus_customer'
      @user.save!

      expect(@user).to receive(:with_lock).and_raise(Mongoid::Locker::Errors::DocumentCouldNotGetLock.new(User, @user.id))
      expect(Stripe::Customer).to_not receive(:create)
      expect(Stripe::Subscription).to receive(:create).and_return(@subscription)

      expect { StripeHelper.create_subscription(@user, Plan.yearly_all)  }.to raise_error(BadRequestError)
    end

    it 'ensures the user has a customer account' do
      plan = Plan.all.first
      expect(@user.customer_id).to be_blank

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to receive(:create).and_return(@subscription)

      StripeHelper.create_subscription(@user, plan, nil, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
    end

    it 'does not create a new customer if the user already has a customer account' do
      plan = Plan.all.first
      @user.customer_id = 'cus_customer'
      @user.save!

      expect(Stripe::Customer).to_not receive(:create)
      expect(Stripe::Subscription).to receive(:create).and_return(@subscription)

      StripeHelper.create_subscription(@user, plan)
      expect(@user.customer_id).to eq('cus_customer')
    end

    it 'rejects unknown coupons' do
      plan = Plan.all.first

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to_not receive(:create)

      expect { StripeHelper.create_subscription(@user, plan, 'notacoupon', 'faux_token') }.to raise_error(BadRequestError)
    end

    it 'applies the coupon if one is supplied' do
      plan = Plan.all.find{|p| p.id == Plan.yearly_all.id}

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to receive(:create).with(
        hash_including({coupon: "coupon_free", customer: "cus_customer", items: [{plan: Plan.yearly_all.id}]}), anything()
        ).and_return(@subscription)

      StripeHelper.create_subscription(@user, plan, @coupon, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
      expect(@user.subscriptions).to be_present

      s = @user.subscriptions.first
      expect(s.plan_id).to eq(Plan.yearly_all.id)
      expect(s).to be_active
    end

    it 'does not include a coupon if one is not supplied' do
      plan = Plan.all.find{|p| p.id == Plan.yearly_all.id}

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to receive(:create).with(
        hash_including({customer: "cus_customer", items: [{plan: Plan.yearly_all.id}]}), anything()
        ).and_return(@subscription)

      StripeHelper.create_subscription(@user, plan, @coupon, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
      expect(@user.subscriptions).to be_present

      s = @user.subscriptions.first
      expect(s.plan_id).to eq(Plan.yearly_all.id)
      expect(s).to be_active
    end

    it 'rejects unknown plans' do
      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to_not receive(:create)

      expect { StripeHelper.create_subscription(@user, 'notaplan', nil, 'faux_token') }.to raise_error(BadRequestError)
    end

    it 'starts the user on the plan if successful' do
      plan = Plan.all.find{|p| p.id == Plan.yearly_all.id}

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to receive(:create).and_return(@subscription)

      StripeHelper.create_subscription(@user, plan, @coupon, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
      expect(@user.subscriptions).to be_present

      s = @user.subscriptions.first
      expect(s.plan_id).to eq(Plan.yearly_all.id)
      expect(s).to be_active
    end

    it 'disallows multiple Recalls subscriptions' do
      plan = Plan.all.find{|p| p.id == Plan.yearly_all.id}

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to receive(:create).and_return(@subscription)

      StripeHelper.create_subscription(@user, plan, @coupon, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
      expect(@user.subscriptions).to be_present

      s = @user.subscriptions.first
      expect(s.plan_id).to eq(Plan.yearly_all.id)
      expect(s).to be_active

      expect { StripeHelper.create_subscription(@user, plan) }.to raise_error(BadRequestError)
    end

    it 'cancels a subscription' do
      plan = Plan.all.find{|p| p.id == Plan.yearly_all.id}

      expect(Stripe::Customer).to receive(:create).and_return(@customer)
      expect(Stripe::Subscription).to receive(:create).and_return(@subscription)

      StripeHelper.create_subscription(@user, plan, @coupon, 'faux_token')
      expect(@user.customer_id).to eq('cus_customer')
      expect(@user.subscriptions).to be_present

      s = @user.subscriptions.first
      expect(s.plan_id).to eq(Plan.yearly_all.id)
      expect(s).to be_active

      expect(Stripe::Subscription).to receive(:update).and_return(@ended)
      StripeHelper.cancel_subscription(@user, s.stripe_id)

      @user.reload
      s = @user.subscriptions.first
      expect(s).to be_active
      expect(s.expires_on).to eq(s.renews_on)
    end

    it 'retrieves a subscription' do
      expect(Stripe::Subscription).to receive(:retrieve).and_return(@subscription)

      s = StripeHelper.retrieve_subscription(@subscription.id)
      expect(s).to eq(@subscription)
    end

  end

end
