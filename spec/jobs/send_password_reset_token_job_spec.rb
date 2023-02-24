require 'rails_helper'
include ActiveJob::TestHelper

describe SendPasswordResetTokenJob, type: :request do

  before :example do
    @user = create(:user, preference: p)
    @user.email_confirmed!
    @user.refresh_access_token!
    clear_enqueued_jobs
    clear_performed_jobs
  end

  after :example do
    clear_enqueued_jobs
    clear_performed_jobs
    User.destroy_all
  end

  it 'is enqueued with the User identifier' do
    assert_no_enqueued_jobs

    assert_enqueued_with(job: SendPasswordResetTokenJob, args: [@user.id.to_s], queue: 'users') do
      @user.reset_password!
      expect(@user).to be_needs_reset_token
    end
  end

  it 'gets performed' do
    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      @user.reset_password!
      expect(@user).to be_needs_reset_token
    end

    assert_performed_jobs(1)
  end

  it 'performs with the User identifier' do
    assert_no_enqueued_jobs

    assert_performed_with(job: SendPasswordResetTokenJob, args: [@user.id.to_s], queue: 'users') do
      @user.reset_password!
      expect(@user).to be_needs_reset_token
    end

    assert_performed_jobs(1)
  end

  it 'notes the sending time of the reset token' do
    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      @user.reset_password!
      expect(@user).to be_needs_reset_token
    end

    @user.reload
    expect(@user.reset_password_sent_at).to be >= Time.now.utc.beginning_of_minute

    assert_performed_jobs(1)
  end

end
