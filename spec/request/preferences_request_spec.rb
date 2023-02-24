require 'rails_helper'

describe 'Preference', type: :request do

  describe 'Retrieving the Preferences' do

    before :all do
      @user = create(:user)
      @user.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!
    end

    after :all do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      get "/users/#{@user.id}/preference"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      get "/users/#{@user.id}/preference", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the preference' do
      get "/users/#{@user.id}/preference", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@user.preference.as_json)
    end

    it 'allows workers to retrieve the preferences for another user' do
      get "/users/#{@user.id}/preference", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@user.preference.as_json)
    end

    it 'allows workers to retrieve the preferences for another user by email' do
      get "/users/#{@worker.id}/preference", params: {email: @user.email}, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@user.preference.as_json)
    end

  end

  describe 'Updating a Preference' do

    before :each do
      @user = create(:user, plan: Plan.yearly_vins)
      @user.refresh_access_token!

      @preference = @user.preference
      expect(@preference.categories).to be_present
      @preference.categories = []

      @worker = create(:worker)
      @worker.refresh_access_token!
    end

    after :each do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      put "/users/#{@user.id}/preference", params: { preference: @preference.as_json }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      put "/users/#{@user.id}/preference", params: { preference: @preference.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the updated preference' do
      put "/users/#{@user.id}/preference", params: { preference: @preference.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      @user.reload
      @preference = @user.preference
      expect(@preference.categories).to be_blank

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@preference.as_json)
    end

    it 'returns errors for invalid documents' do
      @preference.categories = ['notacategory']
      put "/users/#{@user.id}/preference", params: { preference: @preference.as_json }, headers: auth_headers(@user)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Categories ')
    end

  end

end
