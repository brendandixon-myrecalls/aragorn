require 'rails_helper'
include ActiveJob::TestHelper

describe 'EmailCoupons', type: :request do

  before :all do
    @admin = create(:admin)
    @admin.refresh_access_token!

    @user = create(:user)
    @user.refresh_access_token!

    @worker = create(:worker)
    @worker.refresh_access_token!

    clear_enqueued_jobs
    clear_performed_jobs
  end

  after :all do
    User.destroy_all

    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe 'Retrieving / searching Coupons' do

    before :example do
      7.times do
        create(:email_coupon)
      end
    end

    after :example do
      EmailCoupon.destroy_all
    end

    it 'requires a signed-in user' do
      get '/email_coupons'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      get '/email_coupons', headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      get '/email_coupons', headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      get '/email_coupons', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns the email coupons' do
      get '/email_coupons', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to be_a(Hash)

      expect(EmailCoupon.from_json(json)).to match_array(EmailCoupon.in_email_order.to_a)
    end

    it 'returns the email coupons in ascending order by email' do
      get '/email_coupons', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to be_a(Hash)

      prev_email = ''
      EmailCoupon.from_json(json).each do |ec|
        expect(ec.email).to be >= prev_email
        prev_email = ec.email
      end
    end

    it 'includes the Stripe coupons' do
      get '/email_coupons', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to be_a(Hash)

      coupons = EmailCoupon.from_json(json).map{|ec| ec.coupon}.uniq

      related = json[:included]
      expect(related).to be_a(Array)
      expect(related.length).to eq(coupons.length)

      related = JsonEnvelope.from_related(json[:included], all_fields: true)
      expect(related).to match_array(coupons)
    end

  end

  describe 'Create a Coupon' do

    before :example do
      @ec = build(:email_coupon)

      clear_enqueued_jobs
      clear_performed_jobs
    end

    after :example do
      EmailCoupon.destroy_all

      clear_enqueued_jobs
      clear_performed_jobs
    end

    it 'requires a signed-in user' do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'creates the email coupon' do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      expect(EmailCoupon.count).to eq(1)
      expect(EmailCoupon.first.email).to eq(@ec.email)
      expect(EmailCoupon.first.coupon_id).to eq(@ec.coupon_id)
    end

    it 'fails if the email already has a coupon' do
      @ec.save!

      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:conflict)
    end

    it 'returns the email coupon' do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(purge_id(EmailCoupon.from_json(json).attributes)).to eq(purge_id(@ec.attributes))
    end

    it 'includes the associated Stripe coupon' do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to be_a(Hash)
      expect(purge_id(EmailCoupon.from_json(json).attributes)).to eq(purge_id(@ec.attributes))

      related = json[:included]
      expect(related).to be_a(Array)
      expect(related.length).to eq(1)

      related = JsonEnvelope.from_related(json[:included], all_fields: true)
      expect(related).to eq([@ec.coupon])
    end

    it 'sends invitation email on creation' do
      assert_no_enqueued_jobs

      assert_enqueued_with(job: SendInvitationJob, args: [@ec.email], queue: 'users') do
        post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@worker)
      end

      assert_enqueued_jobs(1, queue: :users, only: SendInvitationJob)
    end

  end

  describe 'Retrieve a single Coupon' do

    before :example do
      @ec = create(:email_coupon)
    end

    after :example do
      EmailCoupon.destroy_all
    end

    it 'requires a signed-in user' do
      get "/email_coupons/#{@ec.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      get "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      get "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      get "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns the email coupon' do
      get "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(EmailCoupon.from_json(json)).to eq(@ec)
    end

    it 'includes the associated Stripe coupon' do
      get "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to be_a(Hash)
      expect(EmailCoupon.from_json(json)).to eq(@ec)

      related = json[:included]
      expect(related).to be_a(Array)
      expect(related.length).to eq(1)

      related = JsonEnvelope.from_related(json[:included], all_fields: true)
      expect(related).to eq([@ec.coupon])
    end

  end

  describe 'Delete a Coupon' do

    before :example do
      @ec = create(:email_coupon)
    end

    after :example do
      EmailCoupon.destroy_all
    end

    it 'requires a signed-in user' do
      delete "/email_coupons/#{@ec.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      delete "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      delete "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      delete "/email_coupons/#{@ec.id}", as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

  end

end
