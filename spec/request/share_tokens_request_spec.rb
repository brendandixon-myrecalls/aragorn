require 'rails_helper'

describe 'Share Tokens', type: :request do

  before :all do
    @user = create(:user)
    @user.refresh_access_token!
  end

  after :all do
    User.destroy_all
  end

  describe 'Retrieve the Share Token' do

    before :all do
      @recall = create(:recall, state: 'sent')
      @token = @recall.share_token
    end

    after :all do
      Recall.destroy_all
    end

    it 'returns http moved permanently' do
      get "/tokens/#{@token.token}", headers: auth_headers(@user)
      expect(response).to have_http_status(:moved_permanently)
    end

    it 'redirects to the recall path' do
      get "/tokens/#{@token.token}", headers: auth_headers(@user)
      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to be_present
      expect(response.headers['Location']).to eq(recall_url(@recall, token: @token.token))
    end

    it 'the redirect retrieves the recall' do
      get "/tokens/#{@token.token}", headers: auth_headers(@user)
      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to be_present
      expect(response.headers['Location']).to eq(recall_url(@recall, token: @token.token))

      uri = URI::parse(response.headers['Location'])
      get URI::HTTP.build(path: uri.path, query: uri.query).request_uri
      expect(response).to have_http_status(:success)
      expect(response.body).to be_present

      r = Recall.from_json(response.body)
      expect(r).to eq(@recall)
    end

    it 'does not require a signed-in user' do
      get "/tokens/#{@token.token}"
      expect(response).to have_http_status(:moved_permanently)
    end

  end

end
