require 'rails_helper'
include ActiveJob::TestHelper

describe SendEmailConfirmationJob, type: :request do

  before :example do
    @user = create(:user, preference: p)
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

    assert_enqueued_with(job: SendEmailConfirmationJob, args: [@user.id.to_s], queue: 'users') do
      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))

      expect(Stripe::Customer).to receive(:retrieve).and_return(customer)
      expect(customer).to receive(:save).and_return({})

      @user.email = 'adifferentemail@foo.bar'
      @user.save!
      expect(@user).to_not be_email_confirmed
      expect(@user).to be_needs_email_confirmation 
    end
  end

  it 'gets performed' do
    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))

      expect(Stripe::Customer).to receive(:retrieve).and_return(customer)
      expect(customer).to receive(:save).and_return({})

      @user.email = 'adifferentemail@foo.bar'
      @user.save!
      expect(@user).to_not be_email_confirmed
      expect(@user).to be_needs_email_confirmation 
    end

    assert_performed_jobs(1)
  end

  it 'performs with the User identifier' do
    assert_no_enqueued_jobs

    assert_performed_with(job: SendEmailConfirmationJob, args: [@user.id.to_s], queue: 'users') do
      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))

      expect(Stripe::Customer).to receive(:retrieve).and_return(customer)
      expect(customer).to receive(:save).and_return({})

      @user.email = 'adifferentemail@foo.bar'
      @user.save!
      expect(@user).to_not be_email_confirmed
      expect(@user).to be_needs_email_confirmation 
    end

    assert_performed_jobs(1)
  end

  it 'notes the sending time of the email confirmation token' do
    assert_no_enqueued_jobs

    perform_enqueued_jobs do
      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))

      expect(Stripe::Customer).to receive(:retrieve).and_return(customer)
      expect(customer).to receive(:save).and_return({})

      @user.email = 'adifferentemail@foo.bar'
      @user.save!
      expect(@user).to_not be_email_confirmed
    end

    @user.reload
    expect(@user.email_confirmation_sent_at).to be >= Time.now.utc.beginning_of_minute

    assert_performed_jobs(1)
  end

end
