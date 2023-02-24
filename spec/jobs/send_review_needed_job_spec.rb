require 'rails_helper'
include ActiveJob::TestHelper
include ActionMailer::TestHelper

describe SendReviewNeededJob, type: :request do

  before :all do
    @admin = create(:admin)
    @admin.refresh_access_token!

    p = build(:preference, categories: ['food'], distribution: nil, alert_by_email: true)
    @user = create(:user, preference: p)
    @user.refresh_access_token!

    @worker = create(:worker)
    @worker.refresh_access_token!

    clear_enqueued_jobs
    clear_performed_jobs
  end

  after :all do
    User.destroy_all
  end

  before :example do
    @recall = build(:recall, feed_name: 'fda', categories: ['food'], state: 'unreviewed')
    @id = @recall.id
    @recall = @recall.as_json(exclude_self_link: true)
  end

  after :example do
    clear_enqueued_jobs
    clear_performed_jobs
    Recall.destroy_all
  end

  it 'is enqueued by creating an unreviewed Recall' do
    assert_no_enqueued_jobs

    post '/recalls', params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
    expect(response).to have_http_status(:success)

    assert_enqueued_jobs(1, queue: :admin)
  end

  it 'is enqueued with no arguments' do
    assert_no_enqueued_jobs

    assert_enqueued_with(job: SendReviewNeededJob, args: [], queue: 'admin') do
      post '/recalls', params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end
  end

  it 'gets performed' do
    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      post '/recalls', params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    assert_performed_jobs(1)
  end

  it 'performs with no arguments' do
    assert_no_enqueued_jobs

    assert_performed_with(job: SendReviewNeededJob, args: [], queue: 'admin') do
      post '/recalls', params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    assert_performed_jobs(1)
  end

  it 'sends mail to administrators' do
    assert_emails 0
    assert_no_enqueued_emails
    assert_no_enqueued_jobs

    assert_emails 1 do
      perform_enqueued_jobs do
        post '/recalls', params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
        expect(response).to have_http_status(:success)
      end
    end

    assert_performed_jobs(1)
  end

end
