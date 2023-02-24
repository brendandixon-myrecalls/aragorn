require 'rails_helper'
include ActiveJob::TestHelper
include ActionMailer::TestHelper

describe SendNewUsersJob, type: :request do

  before :all do
    @admin = create(:admin)
    @admin.refresh_access_token!

    @worker = create(:worker)
    @worker.refresh_access_token!

    clear_enqueued_jobs
    clear_performed_jobs
  end

  after :all do
    User.destroy_all
  end

  before :example do
    @user = build(:user)
    @json = @user.as_json
    @json[:data][:attributes].merge!({ password: 'pa$$W0rdpa$$W0rd' })
  end

  after :example do
    clear_enqueued_jobs
    clear_performed_jobs
    User.destroy_all
  end

  it 'is enqueued by creating a new User' do
    assert_no_enqueued_jobs

    post '/users', params: { user: @json, recaptcha: 'ignored' }, as: :json, headers: auth_headers(@admin)
    expect(response).to have_http_status(:success)

    assert_enqueued_jobs(1, queue: :admin)
  end

  it 'is enqueued with no arguments' do
    assert_no_enqueued_jobs

    assert_enqueued_with(job: SendNewUsersJob, args: [], queue: 'admin') do
      post '/users', params: { user: @json, recaptcha: 'ignored' }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end
  end

  it 'gets performed' do
    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      post '/users', params: { user: @json, recaptcha: 'ignored' }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    assert_performed_jobs(1, queue: :admin)
  end

  it 'performs with no arguments' do
    assert_no_enqueued_jobs

    assert_performed_with(job: SendNewUsersJob, args: [], queue: 'admin') do
      post '/users', params: { user: @json, recaptcha: 'ignored' }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    assert_performed_jobs(1, queue: :admin)
  end

  it 'sends mail to administrators' do
    assert_emails 0
    assert_no_enqueued_emails
    assert_no_enqueued_jobs

    assert_emails 1 do
      perform_enqueued_jobs do
        post '/users', params: { user: @json, recaptcha: 'ignored' }, as: :json, headers: auth_headers(@admin)
        expect(response).to have_http_status(:success)
      end
    end

    assert_performed_jobs(1, queue: :admin)
  end

end
