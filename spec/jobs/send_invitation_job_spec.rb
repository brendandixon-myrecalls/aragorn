require 'rails_helper'
include ActiveJob::TestHelper

describe SendInvitationJob, type: :request do

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

  before :example do
    @ec = build(:email_coupon)
    clear_enqueued_jobs
    clear_performed_jobs
  end

  after :example do
    clear_enqueued_jobs
    clear_performed_jobs
    EmailCoupon.destroy_all
  end

  it 'is enqueued with the email address' do
    assert_no_enqueued_jobs

    assert_enqueued_with(job: SendInvitationJob, args: [@ec.email], queue: 'users') do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end
  end

  it 'gets performed' do
    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    assert_performed_jobs(1)
  end

  it 'performs with the email address' do
    assert_no_enqueued_jobs

    assert_performed_with(job: SendInvitationJob, args: [@ec.email], queue: 'users') do
      post '/email_coupons', params: { emailCoupon: @ec }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    assert_performed_jobs(1)
  end

end
