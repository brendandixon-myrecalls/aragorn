require 'rails_helper'

describe 'Plans', type: :request do

  describe 'Retrieving Plans' do

    before :all do
      @admin = create(:admin)
      @admin.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!

      @user = create(:user)
      @user.refresh_access_token!

      @ec = create(:email_coupon, email: @user.email, coupon_id: Coupon.free_forever.id)
    end

    after :all do
      EmailCoupon.destroy_all
      User.destroy_all
    end

    it 'does not require a signed-in user' do
      get "/plans"
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for administrators' do
      get "/plans", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      get "/plans", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for users' do
      get "/plans", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns all the known plans' do
      get "/plans", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(Plan.all.length)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(Plan.all.length)

      data = Plan.from_json(json, all_fields: true)
      expect(data.sort).to eq(Plan.all.sort)
    end

    it 'includes any coupons for current user' do
      get "/plans", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(Plan.all.length)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(Plan.all.length)

      related = json[:included]
      expect(related).to be_a(Array)
      expect(related.length).to eq(1)

      related = JsonEnvelope.from_related(json[:included], all_fields: true)
      expect(related).to eq([@ec.coupon])
    end

    it 'workers can retreive coupons for another user' do
      get "/plans", params: { email: @user.email }, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(Plan.all.length)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(Plan.all.length)

      related = json[:included]
      expect(related).to be_a(Array)
      expect(related.length).to eq(1)

      related = JsonEnvelope.from_related(json[:included], all_fields: true)
      expect(related).to eq([@ec.coupon])
    end

  end

end
