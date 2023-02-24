require 'rails_helper'
include ActiveJob::TestHelper

describe SendAlertsJob, type: :request do

  before :all do
    @admin = create(:admin)
    @admin.refresh_access_token!

    p = build(:preference,
      categories: ['food'],
      distribution: USRegions::REGIONS[:nationwide],
      alert_by_email: true,
      risk: ['probable', 'possible'])
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
    @recall = build(:recall, feed_name: 'fda', categories: ['food'], risk: 'possible')
    @id = @recall.id
    @recall = @recall.as_json(exclude_self_link: true)
  end

  after :example do
    clear_enqueued_jobs
    clear_performed_jobs
    Recall.destroy_all
  end

  it 'is enqueued by recall creation' do
    assert_no_enqueued_jobs

    post '/recalls', params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
    expect(response).to have_http_status(:success)

    assert_enqueued_jobs(1, queue: :alerts)
  end

  it 'is enqueued to send recall alerts' do
    assert_no_enqueued_jobs

    assert_enqueued_with(job: SendAlertsJob, args: ["send_recall_alerts"], queue: 'alerts') do
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

  it 'invokes the Lambda function' do
    invoked = false
    allow(AwsHelper).to receive(:invoke) {|name, **options|
      expect(name).to be(SendAlertsJob::ALERTER_FUNCTION)
      invoked = true
      true
    }

    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      post '/recalls', params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    expect(invoked).to be true
    assert_performed_jobs(1)
  end

end
