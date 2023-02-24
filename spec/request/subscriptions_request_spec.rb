require 'rails_helper'

describe 'Subscription', type: :request do

  describe 'Retrieving Subscriptions' do

    before :all do
      @user = create(:user)

      5.times do |i|
        travel_to i.months.ago do
          s = build(:subscription, plan: Plan.yearly_vins)
          expire_at(s, Time.now) if i >= 4
          @user.subscriptions << s
        end
      end
      @user.save!
      expect(@user.active_subscriptions.length).to eq(@user.subscriptions.length - 1)

      @user.reload
      @user.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!
    end

    after :all do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      get "/users/#{@user.id}/subscriptions"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      get "/users/#{@user.id}/subscriptions", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'allows workers to retrieve the subscriptions for another user' do
      get "/users/#{@user.id}/subscriptions", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      count = @user.active_subscriptions.length
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)
    end

    it 'allows workers to retrieve the subscriptions for another user by email' do
      get "/users/#{@worker.id}/subscriptions", params: {email: @user.email}, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      count = @user.active_subscriptions.length
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)
    end

    it 'returns the active subscriptions for the user' do
      get "/users/#{@user.id}/subscriptions", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      count = @user.active_subscriptions.length
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      subscriptions = @user.active_subscriptions.sort
      data.each_with_index do |d, i|
        expect(d).to eq(subscriptions[i].as_json(exclude_self_link: true)[:data])
      end
    end

    it 'returns all the subscriptions for the user' do
      get "/users/#{@user.id}/subscriptions", params: { all: true }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      count = @user.subscriptions.length
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      subscriptions = @user.subscriptions.sort
      data.each_with_index do |d, i|
        expect(d).to eq(subscriptions[i].as_json(exclude_self_link: true)[:data])
      end
    end

  end

  describe 'Creating a Subscription' do

    before :example do
      @coupon = Coupon.all.first
      @customer = Stripe::Customer.construct_from(load_stripe('customer.json'))
      @subscription = Stripe::Subscription.construct_from(load_stripe('all_subscription.json'))
      @vins_subscription = Stripe::Subscription.construct_from(load_stripe('vins_subscription.json'))

      @user = create(:user, count_subscriptions: 0)
      @user.refresh_access_token!

      @other = create(:user, count_subscriptions: 0)
      @other.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!

      EmailCoupon.create(email: @other.email, coupon: @coupon)
    end

    after :example do
      EmailCoupon.destroy_all
      User.destroy_all
    end

    it 'requires a signed-in user' do
      json = { plan_id: Plan.yearly_all.id }
      post "/users/#{@user.id}/subscriptions", params: json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'successfully subscribes a user' do
      allow(Stripe::Customer).to receive(:create).and_return(@customer)

      args = { customer: @customer.id, items: [{ plan: Plan.yearly_all.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@subscription)

      expect(@user).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, token: 'faux_token' }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:created)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
    end

    it 'returns the new subscription' do
      allow(Stripe::Customer).to receive(:create).and_return(@customer)

      args = { customer: @customer.id, items: [{ plan: Plan.yearly_all.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@subscription)

      expect(@user).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, token: 'faux_token' }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:created)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@user.recall_subscription.as_json)
    end

    it 'applies a coupon for the user' do
      allow(Stripe::Customer).to receive(:create).and_return(@customer)

      args = { customer: @customer.id, coupon: @coupon.id, items: [{ plan: Plan.yearly_all.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@subscription)

      expect(@other).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, token: 'faux_token' }
      post "/users/#{@other.id}/subscriptions", params: json, headers: auth_headers(@other)
      expect(response).to have_http_status(:created)

      @other.reload
      expect(@other).to be_subscribed_to(Plan.yearly_all)
    end

    it 'includes the provided Stripe token' do
      token = Helper.generate_token
      args = { email: @user.email, source: token}
      allow(Stripe::Customer).to receive(:create).with(args, any_args).and_return(@customer)

      args = { customer: @customer.id, items: [{ plan: Plan.yearly_all.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@subscription)

      expect(@user).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, token: token }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:created)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
    end

    it 'allows a user to subscribe to multiple plans' do
      allow(Stripe::Customer).to receive(:create).and_return(@customer)

      args = { customer: @customer.id, items: [{ plan: Plan.yearly_all.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@subscription)

      args = { customer: @customer.id, items: [{ plan: Plan.yearly_vins.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@vins_subscription)

      expect(@user).to be_inactive

      json = { plan: Plan.yearly_all.id, token: 'faux_token' }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:created)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_vins.id }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:created)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
      expect(@user).to be_subscribed_to(Plan.yearly_vins)
    end

    it 'allows workers to subscribe another user' do
      allow(Stripe::Customer).to receive(:create).and_return(@customer)

      args = { customer: @customer.id, items: [{ plan: Plan.yearly_all.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@subscription)

      expect(@user).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, token: 'faux_token' }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:created)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
    end

    it 'allows workers to subscribe another user by email address' do
      allow(Stripe::Customer).to receive(:create).and_return(@customer)

      args = { customer: @customer.id, items: [{ plan: Plan.yearly_all.id }]}
      expect(Stripe::Subscription).to receive(:create).with(args, any_args).and_return(@subscription)

      expect(@user).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, email: @user.email, token: 'faux_token' }
      post "/users/#{@worker.id}/subscriptions", params: json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:created)

      @user.reload
      expect(@user).to be_subscribed_to(Plan.yearly_all)
    end

    it 'ignores non-workers subscribing for other users' do
      expect(@other).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, token: 'faux_token' }
      post "/users/#{@other.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)

      @other.reload
      expect(@other).to_not be_subscribed_to(Plan.yearly_all)

      json = { plan: Plan.yearly_all.id, email: @other.email, token: 'faux_token' }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)

      @other.reload
      expect(@other).to_not be_subscribed_to(Plan.yearly_all)
    end

    it 'rejects unknown plans' do
      json = { plan: 'notaplan', token: 'faux_token' }
      post "/users/#{@user.id}/subscriptions", params: json, headers: auth_headers(@user)
      expect(response).to have_http_status(:bad_request)
    end

  end

  describe 'Retrieving a single Subscription' do

    before :all do
      @user = create(:user)
      @subscription = @user.active_subscriptions.first
      @user.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!
    end

    after :all do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      get "/users/#{@user.id}/subscriptions/#{@subscription.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      get "/users/#{@user.id}/subscriptions/#{@subscription.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the subscription' do
      get "/users/#{@user.id}/subscriptions/#{@subscription.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@subscription.as_json)
    end

    it 'allows workers to retrieve the subscriptions for another user' do
      get "/users/#{@user.id}/subscriptions/#{@subscription.id}", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@subscription.as_json)
    end

    it 'allows workers to retrieve the subscriptions for another user by email' do
      get "/users/#{@worker.id}/subscriptions/#{@subscription.id}", params: {email: @user.email}, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@subscription.as_json)
    end

  end

  describe 'Canceling a Subscription' do

    before :all do
      @ended = Stripe::Subscription.construct_from(load_stripe('ended_subscription.json'))

      @user = create(:user)
      @subscription = @user.active_subscriptions.first
      @subscription.stripe_id = @ended.id
      @user.save!
      @user.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!
    end

    after :all do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      put "/users/#{@user.id}/subscriptions/#{@subscription.id}/cancel"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      args = { cancel_at: nil, cancel_at_period_end: true }
      expect(Stripe::Subscription).to receive(:update).with(@subscription.stripe_id, args, any_args).and_return(@ended)

      put "/users/#{@user.id}/subscriptions/#{@subscription.id}/cancel", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the subscription' do
      args = { cancel_at: nil, cancel_at_period_end: true }
      expect(Stripe::Subscription).to receive(:update).with(@subscription.stripe_id, args, any_args).and_return(@ended)

      put "/users/#{@user.id}/subscriptions/#{@subscription.id}/cancel", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys

      @user.reload

      je = JsonEnvelope.from_json(:subscriptions, json)
      expect(je).to_not be_is_collection
      je.each_datum do |id, attributes|
        id = BSON::ObjectId.from_string(id)
        s = @user.subscription_from_id(id)
        expect(s).to eq(@user.subscriptions.first)
        expect(s).to be_present
        expect(s).to be_active
        expect(s.expires_on).to eq(s.renews_on)
      end
    end

    it 'cancels the subscription' do
      args = { cancel_at: nil, cancel_at_period_end: true }
      expect(Stripe::Subscription).to receive(:update).with(@subscription.stripe_id, args, any_args).and_return(@ended)

      put "/users/#{@user.id}/subscriptions/#{@subscription.id}/cancel", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys

      @user.reload
      s = @user.subscriptions.first
      expect(s).to be_active
      expect(s.expires_on).to eq(s.renews_on)
      travel_to s.expires_on.end_of_grace_period + 1.second do
        expect(s).to be_inactive
      end
    end

    it 'allows workers to cancel the subscriptions for another user' do
      args = { cancel_at: nil, cancel_at_period_end: true }
      expect(Stripe::Subscription).to receive(:update).with(@subscription.stripe_id, args, any_args).and_return(@ended)

      put "/users/#{@user.id}/subscriptions/#{@subscription.id}/cancel", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys

      @user.reload
      s = @user.subscriptions.first
      expect(s).to be_active
      expect(s.expires_on).to eq(s.renews_on)
    end

    it 'allows workers to cancel the subscriptions for another user by email' do
      args = { cancel_at: nil, cancel_at_period_end: true }
      expect(Stripe::Subscription).to receive(:update).with(@subscription.stripe_id, args, any_args).and_return(@ended)

      put "/users/#{@worker.id}/subscriptions/#{@subscription.id}/cancel", params: {email: @user.email}, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys

      @user.reload
      s = @user.subscriptions.first
      expect(s).to be_active
      expect(s.expires_on).to eq(s.renews_on)
    end

  end

end
