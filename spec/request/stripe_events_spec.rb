require 'rails_helper'

describe 'Stripe Events', type: :request do

  def expect_construct_event(event)
    expect(Stripe::Webhook).to receive(:construct_event).and_return(event)
  end

  def load_event(file, plan)
    e = Stripe::Event.construct_from(load_stripe(file))
  end

  def load_subscription(file, plan)
    s = Stripe::Subscription.construct_from(load_stripe(file))
    init_subscription(s, plan)
  end

  def init_subscription(s, plan)
    now = Time.now
    s.cancel_at = nil
    s.cancel_at_period_end = false
    s.canceled_at = nil
    s.current_period_start = now.to_i
    s.current_period_end = (now + plan.duration).to_i
    s.ended_at = nil
    s.status = 'active'
    s
  end

  before :example do
    @customer = Stripe::Customer.construct_from(load_stripe('customer.json'))

    freeze_time do
      @now = Time.now
      @canceled_on = @now + 1.month

      @all_subscription = load_subscription('all_subscription.json', Plan.yearly_all)
      @vins_subscription = load_subscription('vins_subscription.json', Plan.yearly_vins)

      @succeeded = load_event('event_invoice_succeeded.json', Plan.yearly_all)
      @failed = load_event('event_invoice_failed.json', Plan.yearly_all)

      @deleted = load_event('event_subscription_deleted.json', Plan.yearly_all)
      s = @deleted.data.object
      s = init_subscription(s, Plan.yearly_all)
      s.canceled_at =
      s.ended_at = @canceled_on.to_i
      s.status = 'canceled'

      @updated = load_event('event_subscription_updated.json', Plan.yearly_all)
      s = @updated.data.object
      s = init_subscription(s, Plan.yearly_all)
      s.cancel_at = s.current_period_end
      s.cancel_at_period_end = true
      s.canceled_at = @canceled_on.to_i
      s.status = 'active'
    end

    @user = create(:user, customer_id: @customer.id, count_subscriptions: 0)
    @user.synchronize_stripe!(@all_subscription)
    @subscription = @user.subscription_from_stripe_id(@all_subscription.id)
    expect(@subscription).to be_present
    expect(@user).to be_subscribed_to(Plan.yearly_all)
  end

  after :example do
    User.destroy_all
  end

  describe 'Successful Invoice Payment' do

    it 'receives a successful invoice and extends the user subscription' do
      expect_construct_event(@succeeded)

      travel_to 2.years.from_now do
        renews_on = Time.now + Plan.yearly_all.duration

        @all_subscription.current_period_end = renews_on.to_i
        expect(Stripe::Subscription).to receive(:retrieve).and_return(@all_subscription)

        expect(Rails.logger).to_not receive(:warn)
        post '/stripe', params: @succeeded.as_json, as: :json
        expect(response).to have_http_status(:success)

        @user.reload
        s = @user.subscription_from_stripe_id(@all_subscription.id)
        expect(s).to be_present
        expect(s).to be_active
        expect(s.renews_on).to eq(renews_on.end_of_day.beginning_of_minute.utc)
      end
    end

    it 'logs a warning if the customer identifier does not map to a known user' do
      expect_construct_event(@succeeded)
      @user.customer_id = generate_stripe_id(:customer)
      @user.save!

      travel_to 2.years.from_now do
        renews_on = @subscription.renews_on

        expect(Stripe::Subscription).to_not receive(:retrieve)

        expect(Rails.logger).to receive(:warn)
        post '/stripe', params: @succeeded.as_json, as: :json
        expect(response).to have_http_status(:success)

        @user.reload
        expect(@user).to be_subscribed_to(Plan.yearly_all)
        expect(@user.subscription_from_stripe_id(@all_subscription.id).renews_on).to eq(renews_on)
      end
    end

    it 'creates the subscription if identifier does not map to a user subscription' do
      expect_construct_event(@succeeded)

      @subscription.stripe_id = generate_stripe_id(:subscription)
      @user.save!

      expect(Stripe::Subscription).to receive(:retrieve).and_return(@vins_subscription)

      expect(Rails.logger).to_not receive(:warn)
      post '/stripe', params: @succeeded.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
      expect(@user).to be_subscribed_to(Plan.yearly_vins)
    end

    it 'logs a warning if the plan identifier does not match the subscribed plan' do
      expect_construct_event(@succeeded)

      @subscription.plan_id = Plan.yearly_vins.id
      @user.save!

      expect(Stripe::Subscription).to receive(:retrieve).and_return(@all_subscription)

      expect(Rails.logger).to receive(:warn).at_least(:once)
      post '/stripe', params: @succeeded.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_vins)
      expect(@user).to_not be_subscribed_to(Plan.yearly_all)
    end

  end

  describe 'Failed Invoice Payment' do

    it 'receives a failed invoice and changes the user subscription status' do
      expect_construct_event(@failed)

      failed_at = @now + 1.day

      @all_subscription.canceled_at =
      @all_subscription.ended_at = failed_at.to_i
      @all_subscription.status = 'canceled'
      expect(Stripe::Subscription).to receive(:retrieve).and_return(@all_subscription)

      expect(Rails.logger).to_not receive(:warn)
      post '/stripe', params: @failed.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      subscription = @user.subscription_from_stripe_id(@all_subscription.id)
      expect(subscription).to be_is_expired(failed_at.end_of_grace_period + 1.second)
    end

    it 'logs a warning if the customer identifier does not map to a known user' do
      expect_construct_event(@failed)
      @user.customer_id = generate_stripe_id(:customer)
      @user.save!

      renews_on = @subscription.renews_on

      expect(Stripe::Subscription).to_not receive(:retrieve)

      expect(Rails.logger).to receive(:warn)
      post '/stripe', params: @failed.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
      expect(@user.subscription_from_stripe_id(@all_subscription.id).renews_on).to eq(renews_on)
    end

    it 'logs a warning if the subscription identifier does not map to a user subscription' do
      expect_construct_event(@failed)

      stripe_id = generate_stripe_id(:subscription)
      renews_on = @subscription.renews_on
      @subscription.stripe_id = stripe_id
      @user.save!

      @all_subscription.canceled_at =
      @all_subscription.ended_at = (@now + 1.day).to_i
      @all_subscription.status = 'unpaid'
      expect(Stripe::Subscription).to receive(:retrieve).and_return(@all_subscription)

      expect(Rails.logger).to receive(:warn).at_least(:once)
      post '/stripe', params: @failed.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
      expect(@user.subscription_from_stripe_id(stripe_id).renews_on).to eq(renews_on)
    end

    it 'logs a warning if the plan identifier match the subscribed plan' do
      expect_construct_event(@failed)

      renews_on = @subscription.renews_on
      @subscription.plan_id = Plan.yearly_vins.id
      @user.save!

      expect(Stripe::Subscription).to receive(:retrieve).and_return(@all_subscription)

      expect(Rails.logger).to receive(:warn).at_least(:once)
      post '/stripe', params: @failed.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_vins)
      expect(@user.subscription_from_stripe_id(@all_subscription.id).renews_on).to eq(renews_on)
    end

  end

  describe 'Subscription Deleted' do

    it 'cancels the user subscription' do
      expect_construct_event(@deleted)

      expect(Rails.logger).to_not receive(:warn)
      post '/stripe', params: @deleted.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
      travel_to @canceled_on.end_of_grace_period { expect(@user).to_not be_subscribed_to(Plan.yearly_all) }
    end

    it 'logs a warning if the customer identifier does not map to a known user' do
      expect_construct_event(@deleted)

      @user.customer_id = generate_stripe_id(:customer)
      @user.save!

      expect(Rails.logger).to receive(:warn)
      post '/stripe', params: @deleted.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
    end

    it 'logs a warning if identifier does not map to a user subscription' do
      expect_construct_event(@deleted)

      @subscription.stripe_id = generate_stripe_id(:subscription)
      @user.save!

      expect(Rails.logger).to receive(:warn).at_least(:once)
      post '/stripe', params: @deleted.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
    end

    it 'logs a warning if the plan identifier does not match the subscribed plan' do
      expect_construct_event(@deleted)

      @subscription.plan_id = Plan.yearly_vins.id
      @user.save!

      expect(Rails.logger).to receive(:warn).at_least(:once)
      post '/stripe', params: @deleted.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_vins)
      expect(@user).to_not be_subscribed_to(Plan.yearly_all)
    end

  end

  describe 'Subscription Updated' do

    it 'updates the user subscription' do
      expect_construct_event(@updated)

      expect(Rails.logger).to_not receive(:warn)
      post '/stripe', params: @updated.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      s = @user.subscriptions_for_plan(Plan.yearly_all).first
      expect(s).to be_present
      expect(s).to be_active
      expect(s.expires_on).to eq(s.renews_on)
      travel_to s.expires_on.end_of_grace_period { expect(s).to_not be_active }
    end

    it 'logs a warning if the customer identifier does not map to a known user' do
      expect_construct_event(@updated)

      @user.customer_id = generate_stripe_id(:customer)
      @user.save!

      expect(Rails.logger).to receive(:warn)
      post '/stripe', params: @updated.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
    end

    it 'creates the subscription if identifier does not map to a user subscription' do
      expect_construct_event(@updated)

      @subscription.plan_id = Plan.yearly_vins.id
      @subscription.stripe_id = generate_stripe_id(:subscription)
      @user.save!

      expect(Rails.logger).to_not receive(:warn)
      post '/stripe', params: @updated.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
      expect(@user).to be_subscribed_to(Plan.yearly_vins)
    end

    it 'logs a warning if the plan identifier does not match the subscribed plan' do
      expect_construct_event(@updated)

      @subscription.plan_id = Plan.yearly_vins.id
      @user.save!

      expect(Rails.logger).to receive(:warn).at_least(:once)
      post '/stripe', params: @updated.as_json, as: :json
      expect(response).to have_http_status(:success)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_vins)
      expect(@user).to_not be_subscribed_to(Plan.yearly_all)
    end

  end

end
