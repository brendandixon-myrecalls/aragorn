require 'rails_helper'
include ActiveJob::TestHelper

describe 'Authentication', type: :request do

  describe 'Signing In' do

    before :example do
      @u = create(:user)
      expect(@u.access_token).to be_blank
    end

    after :example do
      @u.destroy
    end

    it 'returns http success' do
      post '/signin', params: { email: @u.email, password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:success)
    end

    it 'ensures the email is in lowercase' do
      post '/signin', params: { email: @u.email.upcase, password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:success)
    end

    it 'strips leading and trailing space from the email address' do
      post '/signin', params: { email: "    #{@u.email}   ", password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:success)
    end

    it 'strips leading and trailing space from the password' do
      post '/signin', params: { email: @u.email, password: '           pa$$W0rdpa$$W0rd      ' }
      expect(response).to have_http_status(:success)
    end

    it 'returns returns the JsonWebToken' do
      post '/signin', params: { email: @u.email, password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:success)

      expect(response.body).to be_present

      json = JSON.parse(response.body).with_indifferent_access
      expect(json).to have_key(:accessToken)
      expect(json[:accessToken]).to be_present
    end

    it 'does not change the the JsonWebToken' do
      @u.refresh_access_token!
      token = @u.access_token

      post '/signin', params: { email: @u.email, password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:success)

      expect(response.body).to be_present

      @u = User.find(@u.id)
      expect(@u.access_token).to be_present

      json = JSON.parse(response.body).with_indifferent_access
      expect(json).to have_key(:accessToken)
      expect(json[:accessToken]).to be_present

      expect(token).to eq(json[:accessToken])
      expect(@u.access_token).to eq(json[:accessToken])
    end

    it 'returns a new token for an expired token' do
      @u.refresh_access_token!(1.day.ago)
      token = @u.access_token

      expect(token).to be_present
      expect(JsonWebToken.valid?(token, @u.id)).to be false

      post '/signin', params: { email: @u.email, password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body).with_indifferent_access
      expect(json).to have_key(:accessToken)
      expect(json[:accessToken]).to be_present
      expect(json[:accessToken]).to_not eq(token)
    end

    it 'returns HTTP Unauthorized for unrecognized email addresses' do
      post '/signin', params: { email: 'unknown@unknown.com', password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns HTTP Unauthorized for unrecognized passwords' do
      post '/signin', params: { email: @u.email, password: 'notthepassword' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'locks the user out for too many failures' do
      Constants::MAXIMUM_AUTHENTICATION_FAILURES.times do
        post '/signin', params: { email: @u.email, password: 'notthepassword' }
        expect(response).to have_http_status(:unauthorized)
      end

      @u.reload
      expect(@u).to be_account_locked
    end

    it 'a successful signin clears the failure count' do
      (Constants::MAXIMUM_AUTHENTICATION_FAILURES-1).times do
        post '/signin', params: { email: @u.email, password: 'notthepassword' }
        expect(response).to have_http_status(:unauthorized)
      end

      @u.reload
      expect(@u.failed_attempts).to eq(Constants::MAXIMUM_AUTHENTICATION_FAILURES-1)

      post '/signin', params: { email: @u.email, password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:success)

      @u.reload
      expect(@u.failed_attempts).to eq(0)
    end

    it 'returns HTTP Unauthorized for a locked out user' do
      @u.lock_account!
      expect(@u).to be_account_locked

      post '/signin', params: { email: @u.email, password: 'pa$$W0rdpa$$W0rd' }
      expect(response).to have_http_status(:unauthorized)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(401)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to include('locked')
    end

  end

  describe 'Signing Out' do

    before :example do
      @u = create(:user)
      @u.refresh_access_token!
    end

    after :example do
      @u.destroy
    end

    it 'returns http success' do
      delete '/signout', headers: auth_headers(@u)
      expect(response).to have_http_status(:success)
    end

    it 'clears the User access token' do
      delete '/signout', headers: auth_headers(@u)
      expect(response).to have_http_status(:success)

      expect(User.find(@u.id).access_token).to be_blank
    end

  end

  describe 'Refreshing the Token' do

    before :example do
      @u = create(:user)
      @u.refresh_access_token!(1.day.from_now)
      expect(@u.access_token).to be_present
    end

    after :example do
      @u.destroy
    end

    it 'refreshes a valid JsonWebToken' do
      get '/refresh', headers: auth_headers(@u)

      expect(response).to have_http_status(:success)
      expect(response.body).to be_present

      json = JSON.parse(response.body).with_indifferent_access
      expect(json).to have_key(:accessToken)
      expect(json[:accessToken]).to be_present

      exp = Helper.generate_access_token_expiration - 1.day
      expect(JsonWebToken.valid?(json[:accessToken], @u.id, exp)).to be true
    end

    it 'rejects if the JsonWebToken is stale' do
      @u.refresh_access_token!(3.days.ago)
      get '/refresh', headers: auth_headers(@u)

      expect(response).to have_http_status(:unauthorized)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(401)

      expect(User.find(@u.id).access_token).to eq(@u.access_token)
    end

  end

  describe 'Email / Phone Confirmation' do

    before :example do
      @u = create(:user, phone: '123.456.7890')
      @u.refresh_access_token!

      @u.email_confirmed!
      expect(@u).to be_email_confirmed

      @u.phone_confirmed!
      expect(@u).to be_phone_confirmed

      clear_enqueued_jobs
      clear_performed_jobs
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      @u.destroy
    end

    it 'marks the email unconfirmed' do
      get "/confirm?email", headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      @u.reload
      expect(@u).to_not be_email_confirmed
    end

    it 'enqueues the confirmation email job' do
      assert_no_enqueued_jobs
      
      get "/confirm?email", headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      assert_enqueued_jobs(1, queue: :users)
    end

    it 'confirms email with an email confirmation token' do
      @u.email_unconfirmed!
      expect(@u).to_not be_email_confirmed

      post "/confirm?token=#{@u.email_confirmation_token}", headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      @u.reload
      expect(@u).to be_email_confirmed
    end

    it 'strips leading and trailing space from the confirmation token' do
      @u.email_unconfirmed!
      expect(@u).to_not be_email_confirmed

      post "/confirm?token=        #{@u.email_confirmation_token}    ", headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      @u.reload
      expect(@u).to be_email_confirmed
    end

    it 'marks the phone unconfirmed' do
      get "/confirm?phone", headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      @u.reload
      expect(@u).to_not be_phone_confirmed
    end

    it 'confirms phone with a phone confirmation token' do
      @u.phone_unconfirmed!
      expect(@u).to_not be_phone_confirmed

      post "/confirm?token=#{@u.phone_confirmation_token}", headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      @u.reload
      expect(@u).to be_phone_confirmed
    end

    it 'returns an HTTP Bad Request (400) if neither email nor phone is specified' do
      get "/confirm", headers: auth_headers(@u)
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns an HTTP Bad Request (400) for unknown tokens' do
      @u.email_unconfirmed!
      @u.phone_unconfirmed!

      post "/confirm?token=#{Helper.generate_token}", headers: auth_headers(@u)
      expect(response).to have_http_status(:bad_request)
    end

  end

  describe 'Password Reset' do

    before :example do
      @u = create(:user)
      @u.email_confirmed!
      @u.refresh_access_token!
      @pw = 'pa$$W0rdpa$$W0rd'.reverse
      clear_enqueued_jobs
      clear_performed_jobs
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      @u.destroy
    end

    it 'resets the password for the authenticated user' do
      digest = @u.password_digest

      get '/reset?recaptcha=ignored', headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      @u.reload
      expect(@u.password_digest).to_not eq(digest)
    end

    it 'clears the password for the user specified by email' do
      digest = @u.password_digest

      get "/reset?email=#{@u.email}&recaptcha=ignored"
      expect(response).to have_http_status(:ok)

      @u.reload
      expect(@u.password_digest).to_not eq(digest)
    end

    it 'reset returns HTTP Unauthorized (401) for unrecognized users' do
      get '/reset?email=noone@nomail.com&recaptcha=ignored'
      expect(response).to have_http_status(:unauthorized)

      @u.reload
      expect(@u.reset_password_token).to_not be_present
    end

    it 'reset returns HTTP Unauthorized (401) if the ReCAPTCHA token is mising' do
      get '/reset?email=noone@nomail.com'
      expect(response).to have_http_status(:unauthorized)

      @u.reload
      expect(@u.reset_password_token).to_not be_present
    end

    it 'enqueues a job to send the password reset mail' do
      assert_no_enqueued_jobs

      get '/reset?recaptcha=ignored', headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      assert_enqueued_jobs(1, queue: :users)
    end

    it 'sets the password for the authenticated user' do
      @u.reset_password!
      post "/reset?password=#{@pw}&token=#{@u.reset_password_token}", headers: auth_headers(@u)
      expect(response).to have_http_status(:ok)

      delete '/signout', headers: auth_headers(@u)
      expect(response).to have_http_status(:success)

      post '/signin', params: { email: @u.email, password: @pw }
      expect(response).to have_http_status(:success)
    end

    it 'sets the password for the user specified by email' do
      @u.reset_password!
      post "/reset?password=#{@pw}&token=#{@u.reset_password_token}&email=#{@u.email}"
      expect(response).to have_http_status(:ok)

      delete '/signout', headers: auth_headers(@u)
      expect(response).to have_http_status(:success)

      post '/signin', params: { email: @u.email, password: @pw }
      expect(response).to have_http_status(:success)
    end

    it 'set returns HTTP Unauthorized (401) for unrecognized users' do
      @u.reset_password!
      post "/reset?password=#{@pw}email=noone@nomail.com&token=#{@u.reset_password_token}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'set returns HTTP Unauthorized (401) for unrecognized tokens' do
      @u.reset_password!
      post "/reset?password=#{@pw}email=noone@nomail.com&token=#{Helper.generate_token}"
      expect(response).to have_http_status(:unauthorized)
    end

  end

  describe 'Authentication' do

    before :example do
      @u = create(:user)
      @u.refresh_access_token!
    end

    after :example do
      @u.destroy
    end

    it 'accepts a valid JsonWebToken' do
      get "/users/#{@u.id}", headers: auth_headers(@u)
      expect(response).to have_http_status(:success)
    end

    it 'rejects an invalid JsonWebToken' do
      @u.access_token = 'something that is most certainly not an access token'
      get "/users/#{@u.id}", headers: auth_headers(@u)

      expect(response).to have_http_status(:unauthorized)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(401)
    end

    it 'rejects a stale JsonWebToken' do
      @token = @u.refresh_access_token!(3.days.ago)
      @u.access_token = @token
      @u.update_attribute(:access_token, @token)
      get "/users/#{@u.id}", headers: auth_headers(@u)

      expect(response).to have_http_status(:unauthorized)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(401)
    end

    it 'rejects a locked user' do
      @u.lock_account!
      get "/users/#{@u.id}", headers: auth_headers(@u)

      expect(response).to have_http_status(:unauthorized)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(401)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to include('locked')
    end

    it 'rejects if the JsonWebToken no longer matches' do
      headers = auth_headers(@u)
      @u.refresh_access_token!
      get "/users/#{@u.id}", headers: headers

      expect(response).to have_http_status(:unauthorized)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(401)
    end

  end

  describe 'Validation' do

    before :example do
      @u = create(:user)
      @u.refresh_access_token!
    end

    after :example do
      @u.destroy
    end

    it 'accepts a valid JsonWebToken' do
      head "/validate", headers: auth_headers(@u)
      expect(response).to have_http_status(:success)
    end

    it 'rejects an expired JsonWebToken' do
      @u.refresh_access_token!(1.day.ago)
      head "/validate", headers: auth_headers(@u)
      expect(response).to have_http_status(:unauthorized)
    end

  end

end
