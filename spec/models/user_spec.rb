require 'rails_helper'
include ActiveJob::TestHelper

describe User, type: :model do

  before :all do
    User.destroy_all
  end

  context 'Basic Validation' do

    before :example do
      @u = build(:user)
    end

    after :example do
      User.destroy_all
    end

    it 'validates' do
      expect(@u).to be_valid
    end

    # Note:
    # - The Emailable and Phoneable modules contain the core logic
    # - Robust tests exist for both modules
    # - These tests are mere existence checks
    it 'requires an email' do
      @u.email = ''
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:email)

      @u.email = nil
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:email)
    end

    it 'normalizes email addresses to lowercase' do
      @u.email = 'FOOBAR@BAR.COM'
      expect(@u).to be_valid
      expect(@u.email).to eq('foobar@bar.com')
    end

    it 'strips leading and trailing spaces from the email address' do
      @u.email = '             fooBAR@BAR.com          '
      expect(@u).to be_valid
      expect(@u.email).to eq('foobar@bar.com')
    end

    it 'rejects malformed email addresses' do
      @u.email = 'not an email address'
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:email)
    end

    it 'rejects duplicate email addresses' do
      u = create(:user)
      @u.email = u.email
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:email)
    end

    it 'does requires a count of email errors' do
      @u.email_errors = nil
      expect(@u).to_not be_valid
      expect(@u.errors).to have_key(:email_errors)
    end

    it 'allows a count of zero email errors' do
      @u.email_errors = 0
      expect(@u).to be_valid
    end

    it 'allows an integer count of email errors' do
      @u.email_errors = 42
      expect(@u).to be_valid
    end

    it 'rejects negative email error counts' do
      @u.email_errors = -1
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:email_errors)
    end

    it 'rejects non-integer email error counts' do
      @u.email_errors = 'forty-two'
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:email_errors)

      @u.email_errors = 42.0
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:email_errors)
    end

    it 'does not require a phone number' do
      @u.phone = ''
      expect(@u).to be_valid

      @u.phone = nil
      expect(@u).to be_valid
    end

    it 'rejects malformed phone numbers' do
      @u.phone = 'not a phone number'
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:phone)
    end

    it 'will merge errors from the nested preference' do
      @u.preference.audience = ['notanaudience']

      expect(@u).to_not be_valid
      expect(@u.merged_errors.full_messages.first).to start_with('Preference audience ')
    end

    it 'will merge errors from a nested subscription' do
      s = @u.subscriptions.first
      s.started_on = Time.now + 2.years
      s.renews_on = Time.now

      expect(@u).to_not be_valid
      expect(@u.merged_errors.full_messages.first).to start_with('Subscription started on ')
    end

    it 'will merge errors from the vin within a subscription' do
      s = @u.subscriptions.first
      v = s.vins.first
      v.vin = 'notavalidvin'

      expect(@u).to_not be_valid
      expect(@u.merged_errors.full_messages.first).to start_with('Subscription vin notavalidvin is not ')
    end

    it 'will merge errors from the nested vin vehicle' do
      s = @u.subscriptions.first
      v = s.vins.first
      v.vehicle.year = Time.now.year + Vehicle::MAXIMUM_YEARS_HENCE + 1

      expect(@u).to_not be_valid
      expect(@u.merged_errors.full_messages.first).to start_with('Subscription vin vehicle year ')
    end

  end

  context 'Password Validation' do

    before :all do
      @u = build(:user, password: nil)
    end

    it 'requires a password for new users' do
      @u.password = nil
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:password)

      @u.password = ''
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:password)
    end

    it 'accepts a well-formed password' do
      @u.password = 'pa$$W0rd'
      expect(@u).to be_valid
    end

    it 'requires a minimum length password' do
      @u.password = 'pa$$W0r'
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:password)
    end

    it 'disallows excessively long passwords' do
      @u.password = 'pa$$W0rd' + ('!' * ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED)
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:password)
    end

    # Note:
    # - User relies on the PasswordValidator whose tests cover the full array of passwords
    it 'requires moderately complex passwords' do
      @u.password = 'passwordpassword'
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:password)
    end

    it 'strips leading and trailing spaces from the password' do
      @u.password = '         pa$$W0rdpa$$W0rd              '
      expect(@u).to be_valid
      expect(BCrypt::Password.new(@u.password_digest).is_password?('pa$$W0rdpa$$W0rd')).to be true
    end

  end

  context 'Role Validation' do

    before :all do
      @u = build(:user)
    end

    it 'defaults to member' do
      expect(@u.role).to eq('member')
    end

    it 'converts blanks to member' do
      @u.role = nil
      expect(@u).to be_valid
      expect(@u.role).to eq('member')

      @u.role = ''
      expect(@u).to be_valid
      expect(@u.role).to eq('member')
    end

    it 'converts unrecognized values to member' do
      @u.role = 'made-up-role'
      expect(@u).to be_valid
      expect(@u.role).to eq('member')
    end

    it 'accepts admin' do
      @u.role = 'admin'
      expect(@u).to be_valid
    end
  
  end

  context 'Access Token Behavior' do

    before :example do
      @u = create(:user)
    end

    after :example do
      @u.destroy
    end

    it 'creates an access token if the User lacks one' do
      @u.access_token = nil
      @u.save!

      @u.ensure_access_token!
      expect(@u.access_token).to be_present
      expect(JsonWebToken.valid?(@u.access_token, @u.id)).to be true
    end

    it 'creates a new access token if the token is expired' do
      @u.refresh_access_token!(1.day.ago)
      expect(@u.access_token).to be_present

      @u.ensure_access_token!
      expect(@u.access_token).to be_present
      expect(JsonWebToken.valid?(@u.access_token, @u.id)).to be true
    end

    it 'does not change the access token if present and valid' do
      @u.refresh_access_token!
      expect(@u.access_token).to be_present
      expect(JsonWebToken.valid?(@u.access_token, @u.id)).to be true

      token = @u.access_token
      @u.ensure_access_token!
      expect(@u.access_token).to be_present
      expect(JsonWebToken.valid?(@u.access_token, @u.id)).to be true
      expect(@u.access_token).to eq(token)
    end

    it 'creates / refreshes the access token' do
      expect(@u.access_token).to be_blank

      @u.refresh_access_token!
      expect(@u.access_token).to be_present
      expect(JsonWebToken.valid?(@u.access_token, @u.id)).to be true

      token = @u.access_token
      @u = User.find(@u.id)
      expect(@u.access_token).to eq(token)
    end

    it 'clears the lock state when refreshing the access token' do
      Constants::MAXIMUM_AUTHENTICATION_FAILURES.times { @u.authentication_failed! }
      expect(@u).to be_account_locked

      @u.refresh_access_token!
      expect(@u.access_token).to be_present
      expect(JsonWebToken.valid?(@u.access_token, @u.id)).to be true
      expect(@u).to_not be_account_locked
      expect(@u.failed_attempts).to eq(0)
    end

    it 'clears the access token' do
      expect(@u.access_token).to be_blank

      @u.refresh_access_token!
      @u = User.find(@u.id)
      expect(@u.access_token).to be_present

      @u.clear_access_token!
      expect(@u.access_token).to be_blank

      @u = User.find(@u.id)
      expect(@u.access_token).to be_blank
    end

    it 'loads from an access token' do
      expect(@u.access_token).to be_blank

      @u.refresh_access_token!
      expect(@u.access_token).to be_present

      expect(User.from_access_token(@u.access_token)).to eq(@u)
    end

    it 'returns nil if the access token no longer matches' do
      expect(@u.access_token).to be_blank

      @u.refresh_access_token!
      expect(@u.access_token).to be_present
      token = @u.access_token

      @u.refresh_access_token!
      expect(@u.access_token).to be_present

      expect(User.from_access_token(token)).to be_nil
    end

  end

  context 'Authentication Behavior' do

    before :example do
      @u = create(:user)
    end

    after :example do
      @u.destroy
    end

    it 'locks the user after too many failed attempts' do
      travel -1.day
      Constants::MAXIMUM_AUTHENTICATION_FAILURES.times do
        travel 15.minutes
        @u.authentication_failed!
      end
      travel_back

      expect(@u).to be_account_locked
    end

    it 'will not lock the user after a few failed attempts' do
      (Constants::MAXIMUM_AUTHENTICATION_FAILURES-1).times { @u.authentication_failed! }
      expect(@u).to_not be_account_locked
    end

    it 'clears the lock when authentication succeeds' do
      (Constants::MAXIMUM_AUTHENTICATION_FAILURES-1).times { @u.authentication_failed! }
      expect(@u).to_not be_account_locked
      expect(@u.failed_attempts).to eq(Constants::MAXIMUM_AUTHENTICATION_FAILURES-1)

      @u.refresh_access_token!
      expect(@u).to_not be_account_locked
      expect(@u.failed_attempts).to eq(0)
    end

    it 'clears the lock when requested' do
      Constants::MAXIMUM_AUTHENTICATION_FAILURES.times { @u.authentication_failed! }
      expect(@u).to be_account_locked

      @u.unlock_account!
      expect(@u).to_not be_account_locked
    end

  end

  context 'Basic Behavior' do

    before :example do
      @u = create(:user, count_subscriptions: 3)
      @u.email_confirmed!
    end

    after :example do
      User.destroy_all
    end

    it 'does not suspend the email of users with no email errors' do
      expect(@u.email_errors).to eq(0)
      expect(@u).to_not be_email_suspended
    end

    it 'does not suspend the email of users with a few email errors' do
      @u.email_errors = AragornConfig.allowed_email_errors - 1
      expect(@u).to_not be_email_suspended
    end

    it 'does suspend the email of users with excessive email errors' do
      @u.email_errors = AragornConfig.allowed_email_errors
      expect(@u).to be_email_suspended
    end

    it 'marking a few email errors does not affect email confirmation' do
      expect(@u).to_not be_email_suspended
      expect(@u).to be_email_confirmed

      (AragornConfig.allowed_email_errors-1).times {@u.email_errored!}

      expect(@u).to_not be_email_suspended
      expect(@u).to be_email_confirmed
    end

    it 'clears email confirmation if a user has excessive email errors' do
      expect(@u).to_not be_email_suspended
      expect(@u).to be_email_confirmed

      @u.email_errors = AragornConfig.allowed_email_errors
      @u.save!

      expect(@u).to be_email_suspended
      expect(@u).to be_email_unconfirmed
    end

    it 'does not affect email confirmation if marked with a few email errors' do
      (AragornConfig.allowed_email_errors-1).times {@u.email_errored!}
      expect(@u).to_not be_email_suspended
      expect(@u).to be_email_confirmed
    end

    it 'clears email confirmation if marked with excessive email errors' do
      expect(@u).to_not be_email_suspended
      expect(@u).to be_email_confirmed

      AragornConfig.allowed_email_errors.times {@u.email_errored!}

      expect(@u).to be_email_suspended
      expect(@u).to be_email_unconfirmed
    end

    it 'clears the email error count' do
      @u.email_errored!
      expect(@u.email_errors).to eq(1)

      @u.email_succeeded!
      expect(@u.email_errors).to eq(0)
    end

    it 'marks users without a Stripe customer identifier as not registered' do
      reset_subscriptions!(@u, false)
      expect(@u).to_not be_registered
    end

    it 'marks users with a Stripe customer identifier as registered' do
      expect(@u.customer_id).to be_present
      expect(@u).to be_registered
    end

    it 'locates Subscriptions by Plan identifier' do
      @u.subscriptions.each do |s|
        expect(@u.subscriptions_for_plan(s.plan_id)).to include(s)
      end
    end

    it 'rejects unknown Plan identifiers' do
      expect(@u.subscriptions_for_plan('notaplan')).to be_blank
    end

    it 'locates Subscriptions by their id' do
      @u.subscriptions.each do |s|
        expect(@u.subscription_from_id(s.id)).to eq(s)
      end
    end

    it 'rejects unknown Subscription ids' do
      expect(@u.subscription_from_id('notasubscription')).to be_blank
    end

    it 'locates Subscriptions by Stripe identifier' do
      @u.subscriptions.each do |s|
        expect(@u.subscription_from_stripe_id(s.stripe_id)).to eq(s)
      end
    end

    it 'rejects unknown Subscription Stripe identifiers' do
      expect(@u.subscription_from_stripe_id('notasubscription')).to be_blank
    end

    it 'locates Vehicles by their id' do
      @u.subscriptions.each do |s|
        s.vins.each do |v|
          expect(@u.vin_from_id(v.id)).to eq(v)
        end
      end
    end

    it 'rejects unknown Vehicle ids' do
      expect(@u.vin_from_id('notavin')).to be_blank
    end

  end

  context 'Confirmation Behavior' do

    before :example do
      @u = create(:user, phone: '123.456.7890')

      @u.email_unconfirmed!
      @u.phone_unconfirmed!

      clear_enqueued_jobs
      clear_performed_jobs
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      @u.destroy
    end

    it 'confirmation status does not impact validity' do
      expect(@u).to be_valid
    end

    it 'requires email confirmation' do
      expect(@u).to_not be_email_confirmed
      expect(@u).to be_email_unconfirmed
    end

    it 'acknowledges the email confirmation token' do
      t = @u.email_confirmation_token
      expect(t).to be_present

      @u = User.find(@u.id)
      expect(@u.is_email_token?(t)).to be true
    end

    it 'disavows blank and unknown email confirmation tokens' do
      expect(@u.email_confirmation_token).to be_present

      expect(@u.is_email_token?(nil)).to be false
      expect(@u.is_email_token?('')).to be false
      expect(@u.is_email_token?(Helper.generate_token)).to be false
    end

    it 'clears email confirmation state' do
      @u.email_errors = AragornConfig.allowed_email_errors - 1
      @u.email_unconfirmed!

      expect(@u.email_errors).to eq(0)
      expect(@u.email_confirmed_at).to be_nil
      expect(@u.email_confirmation_sent_at).to be_nil
      expect(@u.email_confirmation_token).to be_present
    end

    it 'notes if sending the email token is necessary' do
      expect(@u).to be_needs_email_confirmation
    end

    it 'notes when the email confirmation token was sent' do
      @u.email_unconfirmed!
      expect(@u.email_confirmation_token).to be_present

      @u.send_email_token!
      expect(@u.email_confirmation_token).to_not be_nil
      expect(@u.email_confirmation_sent_at).to be >= Time.now.utc.beginning_of_minute
    end

    it 'confirms an email' do
      expect(@u).to_not be_email_confirmed

      @u.email_confirmed!
      expect(@u).to be_email_confirmed
    end

    it 'resets the email error count when confirming an email' do
      @u.email_errors = AragornConfig.allowed_email_errors
      @u.save!
      expect(@u).to_not be_email_confirmed

      @u.email_confirmed!
      expect(@u.email_errors).to eq(0)
      expect(@u).to be_email_confirmed
      expect(@u).to_not be_email_suspended
    end

    it 'disconfirms the email when updated' do
      @u.email_confirmed!
      expect(@u).to be_email_confirmed

      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))
      expect(Stripe::Customer).to receive(:retrieve).and_return(customer)
      expect(customer).to receive(:save).and_return({})

      @u.email = 'adifferentemail@foo.bar'
      @u.save!

      expect(@u).to_not be_email_confirmed
    end

    it 'enqueues the confirmation email job when email is updated' do
      assert_no_enqueued_jobs

      @u.email_confirmed!
      expect(@u).to be_email_confirmed

      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))
      expect(Stripe::Customer).to receive(:retrieve).and_return(customer)
      expect(customer).to receive(:save).and_return({})

      @u.email = 'adifferentemail@foo.bar'
      @u.save!

      assert_enqueued_jobs(1, queue: :users)
    end

    it 'requires phone confirmation' do
      expect(@u).to_not be_phone_confirmed
      expect(@u).to be_phone_unconfirmed
    end

    it 'acknowledges the phone confirmation token' do
      t = @u.phone_confirmation_token
      expect(t).to be_present

      @u = User.find(@u.id)
      expect(@u.is_phone_token?(t)).to be true
    end

    it 'disavows blank and unknown phone confirmation tokens' do
      expect(@u.phone_confirmation_token).to be_present

      expect(@u.is_phone_token?(nil)).to be false
      expect(@u.is_phone_token?('')).to be false
      expect(@u.is_phone_token?(Helper.generate_token)).to be false
    end

    it 'clears phone confirmation state' do
      @u.phone_unconfirmed!
      expect(@u.phone_confirmed_at).to be_nil
      expect(@u.phone_confirmation_sent_at).to be_nil
      expect(@u.phone_confirmation_token).to be_present
    end

    it 'notes if sending the phone token is necessary' do
      expect(@u).to be_needs_phone_confirmation
    end

    it 'notes when the phone confirmation token was sent' do
      @u.phone_unconfirmed!
      expect(@u.phone_confirmation_token).to be_present

      @u.send_phone_token!
      expect(@u.phone_confirmation_token).to_not be_nil
      expect(@u.phone_confirmation_sent_at).to be >= Time.now.utc.beginning_of_minute
    end

    it 'confirms an phone' do
      expect(@u).to_not be_phone_confirmed

      @u.phone_confirmed!
      expect(@u).to be_phone_confirmed
    end

  end

  context 'Password Behavior' do

    before :example do
      @u = create(:user)
      clear_enqueued_jobs
      clear_performed_jobs
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      @u.destroy
    end

    it 'resets the password state' do
      expect(@u.password_digest).to be_present
      expect(@u.authenticate('pa$$W0rdpa$$W0rd')).to be_truthy

      @u.reset_password!
      expect(@u).to be_valid
      expect(@u.password_digest).to be_present
      expect(@u.authenticate('pa$$W0rdpa$$W0rd')).to be false
    end

    it 'enqueues a job to send the password reset token' do
      assert_no_enqueued_jobs

      @u.email_confirmed!
      @u.reset_password!
      expect(@u).to be_valid
      expect(@u.password_digest).to be_present

      assert_enqueued_jobs(1, queue: :users)
    end

    it 'acknowledges the password reset token' do
      expect(@u.reset_password_token).to be_nil
      @u.reset_password!

      t = @u.reset_password_token
      expect(t).to be_present

      @u = User.find(@u.id)
      expect(@u.is_reset_token?(t)).to be true
    end

    it 'disavows blank and unknown password reset tokens' do
      expect(@u.reset_password_token).to be_nil
      @u.reset_password!
      expect(@u.reset_password_token).to be_present

      @u = User.find(@u.id)
      expect(@u.is_reset_token?(nil)).to be false
      expect(@u.is_reset_token?('')).to be false
      expect(@u.is_reset_token?(Helper.generate_token)).to be false
    end

    it 'clears the token when updating the password' do
      expect(@u.reset_password_token).to be_nil
      @u.reset_password!
      expect(@u.reset_password_token).to be_present

      @u.password = 'pa$$W0rdpa$$W0rd'
      @u.save!
      expect(@u.reset_password_sent_at).to be_blank
      expect(@u.reset_password_token).to be_blank
    end

  end

  context 'Scope Behavior' do

    before :all do
      @email_addresses = []
      @phone_numbers = []

      # Note:
      # - Ensure all subscriptions have the same start time to ease testing
      # - User ensures default preference values for audience, categories, and risk
      #   (if blank) on new member records
      #
      # Profile of created users
      #
      # Number  Categories  Regions   Risk              AlertVins   VinSummary  AlertEmail  AlertPhone  RecallSummary EmailOk PhoneOk Active? ExpiresOn
      #   8     food-only   west      all               x           x           x           -           x             x       x       yes     never
      #   7     allergens   west      probable/possible -           x           -           x           x             x       -       yes     1.year
      #   6     allergens   all       probable          x           x           x           x           x             x       x       no      expired
      #   5     VINs ONLY                               x           x           x           x           x             x       -       yes     never
      #   4     home        midwest   possible          -           x           -           -           x             x       x       yes     never
      #   3     cpsc        northeast possible          -           x           -           -           -             -       x       yes     6.months
      #   2     fda         southeast probable/possible -           -           -           -           -             x       -       yes     never
      #   1     fda         southeast probable/possible -           x           -           -           x             x       x       yes     never
      #
      # Total: 36 plus 1 Guest
      # - #2 targets only professionals, #1 includes professionals and consumers, all others are consumers
      # - #8 is only recalls, #5 is only VINs
      # - #7 has unreviewed VINs
      # - admins and workers will affect email confirmation and inactive user counts
      #
      n = 0
      vehicles = []
      freeze_time do
        @now = Time.now

        # Create Admin and Worker
        p = build(:preference,
          audience: nil,
          categories: nil,
          distribution: nil,
          alert_for_vins: false,
          send_vin_summaries: false,
          alert_by_email: false,
          alert_by_phone: false,
          send_summaries: false,
          risk: nil)

        u = create(:admin, preference: p)
        u.email_confirmed!
        u.phone_unconfirmed!

        u = create(:worker, preference: p)
        u.email_confirmed!
        u.phone_unconfirmed!

        # Create Guest user
        User.guest_user

        # Active Users with never-ending recall subscription
        p = build(:preference,
          categories: ['food'],
          distribution: USRegions::REGIONS[:west],
          alert_for_vins: true,
          send_vin_summaries: true,
          alert_by_email: true,
          alert_by_phone: false,
          send_summaries: true,
          risk: ['probable', 'possible', 'none'])
        8.times do |i|
          u = create(:user,
            created_at: 1.month.ago,
            phone: "123.456.78#{'%02d' % n}",
            preference: p,
            plan: Plan.yearly_recalls)
          u.email_confirmed!
          u.phone_confirmed!
          @email_addresses << u.email if i == 0
          @phone_numbers << u.phone if i == 1
          n += 1
        end

        # Active Users with recall / vin subscription ending in 1 year
        p = build(:preference,
          categories: FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES,
          distribution: USRegions::REGIONS[:west],
          alert_for_vins: false,
          send_vin_summaries: true,
          alert_by_email: false,
          alert_by_phone: true,
          send_summaries: true,
          risk: ['probable', 'possible'])
        7.times do |i|
          u = create(:user,
            created_at: 2.weeks.ago,
            phone: "123.456.78#{'%02d' % n}",
            preference: p)

          s = u.subscriptions.first
          s.expires_on = s.renews_on
          s.vins.each{|v| v.reviewed = false}
          u.save!

          u.email_confirmed!
          u.phone_unconfirmed!
          @email_addresses << u.email if i == 0
          @phone_numbers << u.phone if i == 1
          n += 1
        end

        # Inactive users due to non-payment
        p = build(:preference,
          categories: FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES,
          distribution: USRegions::REGIONS[:nationwide],
          alert_for_vins: true,
          send_vin_summaries: true,
          alert_by_email: true,
          alert_by_phone: true,
          send_summaries: true,
          risk: ['probable'])
        6.times do |i|
          u = create(:user,
            created_at: 1.month.ago,
            phone: "123.456.78#{'%02d' % n}",
            preference: p)

          s = u.subscriptions.first
          s.expires_on = Time.now.start_of_grace_period - 1.day
          s.status = 'unpaid'
          u.save!

          u.email_confirmed!
          u.phone_confirmed!
          @email_addresses << u.email if i == 0
          @phone_numbers << u.phone if i == 1
          n += 1
        end

        # Active users with never-ending vin subscription (no recalls)
        p = build(:preference,
          audience: nil,
          categories: nil,
          distribution: nil,
          alert_for_vins: true,
          send_vin_summaries: true,
          alert_by_email: true,
          alert_by_phone: true,
          send_summaries: true,
          risk: nil)
        5.times do |i|
          u = create(:user,
            created_at: 1.week.ago,
            phone: "123.456.78#{'%02d' % n}",
            preference: p,
            plan: Plan.yearly_vins)
          u.email_confirmed!
          u.phone_unconfirmed!
          @email_addresses << u.email if i == 0
          @phone_numbers << u.phone if i == 1
          n += 1
          vehicles += u.vins.map{|v| Vehicle.new(v.vehicle.attributes.reject{|k,v| k == '_id'})}
        end

        # Active Users with never-ending recall / vin subscription starting 6 months ago
        p = build(:preference,
          categories: FeedConstants::NHTSA_CATEGORIES,
          distribution: USRegions::REGIONS[:midwest],
          alert_for_vins: false,
          send_vin_summaries: true,
          alert_by_email: false,
          alert_by_phone: false,
          send_summaries: true,
          risk: ['possible'])
        4.times do |i|
          u = create(:user,
            created_at: 6.months.ago,
            phone: "123.456.78#{'%02d' % n}",
            preference: p,
            plan_start: 6.months.ago)
          u.email_confirmed!
          u.phone_confirmed!
          @email_addresses << u.email if i == 0
          @phone_numbers << u.phone if i == 1
          n += 1
        end

        # Active Users with recall / vin subscription expiring 6 months from now
        p = build(:preference,
          categories: FeedConstants::CPSC_CATEGORIES,
          distribution: USRegions::REGIONS[:northeast],
          alert_for_vins: false,
          send_vin_summaries: true,
          alert_by_email: false,
          alert_by_phone: false,
          send_summaries: false,
          risk: ['possible'])
        3.times do |i|
          u = create(:user,
            created_at: 6.months.ago,
            phone: "123.456.78#{'%02d' % n}",
            preference: p,
            plan_start: 6.months.ago)

          s = u.subscriptions.first
          s.expires_on = s.renews_on
          u.save!

          u.email_unconfirmed!
          u.phone_confirmed!
          @email_addresses << u.email if i == 0
          @phone_numbers << u.phone if i == 1
          n += 1
        end

        # Active Users with never-ending recall / vin subscription
        p = build(:preference,
          audience: ['professionals'],
          categories: FeedConstants::FDA_CATEGORIES,
          distribution: USRegions::REGIONS[:southeast],
          alert_for_vins: false,
          send_vin_summaries: false,
          alert_by_email: false,
          alert_by_phone: false,
          send_summaries: false,
          risk: ['probable', 'possible'])
        2.times do |i|
          u = create(:user,
            created_at: @now,
            phone: "123.456.78#{'%02d' % n}",
            preference: p)
          u.email_confirmed!
          u.phone_unconfirmed!
          u.update_attribute(:phone, nil)
          @email_addresses << u.email if i == 0
          n += 1
        end

        # Active Users with never-ending recall / vin subscription
        p = build(:preference,
          audience: ['consumers', 'professionals'],
          categories: FeedConstants::FDA_CATEGORIES,
          distribution: USRegions::REGIONS[:southeast],
          alert_for_vins: false,
          send_vin_summaries: true,
          alert_by_email: false,
          alert_by_phone: false,
          send_summaries: true,
          risk: ['probable', 'possible'])
        1.times do |i|
          u = create(:user,
            created_at: @now,
            phone: "123.456.78#{'%02d' % n}",
            preference: p)
          u.email_confirmed!
          u.phone_confirmed!
          @email_addresses << u.email if i == 0
          n += 1
        end
      end

      expect(User.count).to eq(39)

      @carseats_nationwide = create(:recall,
        feed_name: 'carseats',
        categories: ['home'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: 'possible')
      @food_west = create(:recall,
        feed_name: 'fda',
        categories: ['food'],
        distribution: USRegions::REGIONS[:west],
        risk: 'probable')
      @professional = create(:recall,
        feed_name: 'fda',
        audience: ['professionals'],
        categories: ['food'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: 'possible')
      @both = create(:recall,
        feed_name: 'fda',
        audience: ['consumers', 'professionals'],
        categories: ['food'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: 'probable')
      @toys_nationwide = create(:recall,
        feed_name: 'cpsc',
        categories: ['toys'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: 'possible')
      @uninteresting_southeast = create(:recall,
        feed_name: 'cpsc',
        categories: ['commercial'],
        distribution: USRegions::REGIONS[:southeast],
        risk: 'none')
      expect(Recall.count).to eq(6)

      vehicles.uniq!
      expect(vehicles.length).to be > 0
      @vehicle_recall = create(:vehicle_recall, vehicles: vehicles)
      expect(VehicleRecall.count).to eq(1)
    end

    after :all do
      VehicleRecall.destroy_all
      Recall.destroy_all
      User.destroy_all
    end

    it 'finds Users created after a given date' do
      expect(User.created_after(@now - 1.week).count).to eq(11)
    end

    it 'finds Users created before a given date' do
      expect(User.created_before(@now - 3.weeks).count).to eq(21)
    end

    it 'finds Users created during a given date range' do
      expect(User.created_during(@now - 2.weeks, @now).count).to eq(18)
    end

    it 'finds Users created on a specific date' do
      expect(User.created_on(@now-1.month).count).to eq(14)
    end

    it 'finds Users in created order' do
      prev = Constants::DISTANT_PAST
      users = User.in_creation_order
      expect(users.count).to eq(39)
      users.each do |u|
        expect(u.c_at).to be >= prev
        prev = u.c_at
      end
    end

    it 'finds Users in ascending order by email address' do
      users = User.in_email_order(true)
      expect(users.count).to eq(39)
      prev = users.first.email
      users.each do |u|
        expect(u.email).to be >= prev
        prev = u.email
      end
    end

    it 'finds Users in descending order by email address' do
      users = User.in_email_order
      expect(users.count).to eq(39)
      prev = users.first.email
      users.each do |u|
        expect(u.email).to be <= prev
        prev = u.email
      end
    end

    it 'ignores the Guest user' do
      expect(User.is_not_guest.count).to eq(User.count - 1)
    end

    it 'finds Users interested in consumer recalls' do
      au = ['consumers']
      users = User.includes_audience(au)
      expect(users.count).to eq(29)
      users.each do |u|
        expect((u.audience & au).length).to be >= 1
      end
    end

    it 'finds Users interested in professional recalls' do
      au = ['professionals']
      users = User.includes_audience(au)
      expect(users.count).to eq(3)
      users.each do |u|
        expect((u.audience & au).length).to be >= 1
      end
    end

    it 'finds Users interested in all of the audiences' do
      users = User.has_all_audience(FeedConstants::AUDIENCE)
      expect(users.count).to eq(1)
      users.each do |u|
        expect((u.audience & FeedConstants::AUDIENCE).length).to be >= FeedConstants::AUDIENCE.length
      end
    end

    it 'finds Users having some of the requested categories' do
      users = User.includes_categories(['food', 'medical'])
      expect(users.count).to eq(24)
      users.each do |u|
        expect((u.categories & ['food', 'medical']).length).to be >= 1
      end

      users = User.includes_categories(['food'])
      expect(users.count).to eq(24)
      users.each do |u|
        expect((u.categories & ['food']).length).to eq(1)
      end

      users = User.includes_categories(['medical'])
      expect(users.count).to eq(3)
      users.each do |u|
        expect((u.categories & ['medical']).length).to eq(1)
      end
    end

    it 'finds Users having all of the requested categories' do
      users = User.has_all_categories(FeedConstants::ACTS_AS_CONTAMINABLE_CATEGORIES)
      expect(users.count).to eq(0)

      users = User.has_all_categories(FeedConstants::NHTSA_CATEGORIES)
      expect(users.count).to eq(7)
      users.each do |u|
        expect((u.categories & FeedConstants::NHTSA_CATEGORIES).length).to be >= FeedConstants::NHTSA_CATEGORIES.length
      end

      users = User.has_all_categories(FeedConstants::CPSC_CATEGORIES)
      expect(users.count).to eq(3)
      users.each do |u|
        expect((u.categories & FeedConstants::CPSC_CATEGORIES).length).to be >= FeedConstants::CPSC_CATEGORIES.length
      end
    end

    it 'finds Users interested in some of the distribution' do
      r = USRegions::REGIONS[:west] + USRegions::REGIONS[:midwest]
      users = User.includes_distribution(r)
      expect(users.count).to eq(25)
      users.each do |u|
        expect((u.distribution & r).length).to be >= [USRegions::REGIONS[:west].length, USRegions::REGIONS[:midwest].length].min
      end
    end

    it 'finds Users interested in all of the distribution' do
      users = User.has_all_distribution(USRegions::COASTS[:west])
      expect(users.count).to eq(21)
      users.each do |u|
        expect((u.distribution & USRegions::COASTS[:west]).length).to be >= USRegions::COASTS[:west].length
      end
    end

    it 'finds Users interested in recalls with probable risk' do
      ri = ['probable']
      users = User.includes_risk(ri)
      expect(users.count).to eq(24)
      users.each do |u|
        expect((u.risk & ri).length).to be >= 1
      end
    end

    it 'finds Users interested in recalls with possible risk' do
      ri = ['possible']
      users = User.includes_risk(ri)
      expect(users.count).to eq(25)
      users.each do |u|
        expect((u.risk & ri).length).to be >= 1
      end
    end

    it 'finds Users interested in recalls with no risk' do
      ri = ['none']
      users = User.includes_risk(ri)
      expect(users.count).to eq(8)
      users.each do |u|
        expect((u.risk & ri).length).to be >= 1
      end
    end

    it 'finds Users interested in all of the risk' do
      users = User.has_all_risk(FeedConstants::RISK)
      expect(users.count).to eq(8)
      users.each do |u|
        expect((u.risk & FeedConstants::RISK).length).to be >= FeedConstants::RISK.length
      end
    end

    it 'finds Users with email confirmed' do
      users = User.has_confirmed_email
      expect(users.count).to eq(35)
      users.each do |u|
        expect(u).to be_email_confirmed
      end
    end

    it 'finds Users needing email confirmation' do
      users = User.needs_email_confirmation
      expect(users.count).to eq(4)
      users.each do |u|
        expect(u).to_not be_email_confirmed
      end
    end

    it 'finds Users with phone confirmed' do
      users = User.has_confirmed_phone
      expect(users.count).to eq(22)
      users.each do |u|
        expect(u).to be_phone_confirmed
      end
    end

    it 'finds Users needing phone confirmation' do
      users = User.needs_phone_confirmation
      expect(users.count).to eq(14)
      users.each do |u|
        expect(u).to_not be_phone_confirmed
      end
    end

    it 'finds Users with email and phone confirmed' do
      users = User.is_confirmed
      expect(users.count).to eq(21)
      users.each do |u|
        expect(u).to be_email_confirmed
        expect(u).to be_phone_confirmed
      end
    end

    it 'finds Users needing email or phone confirmation' do
      users = User.needs_confirmation
      expect(users.count).to eq(18)
      users.each do |u|
        expect(u.email_confirmed? && u.phone_confirmed?).to be false
      end
    end

    it 'finds Users by email address' do
      @email_addresses.each do |email|
        users = User.with_email(email)
        expect(users.count).to eq(1)
        expect(users.first.email).to eq(email)
      end
    end

    it 'always searches with lowercase email addresses' do
      @email_addresses.each do |email|
        email = email.upcase
        expect(User.where(email: email).count).to eq(0)

        users = User.with_email(email)
        expect(users.count).to eq(1)
        expect(users.first.email).to eq(email.downcase)
      end
    end

    it 'finds Users by phone number' do
      @phone_numbers.each do |phone|
        users = User.with_phone(phone)
        expect(users.count).to eq(1)
        expect(users.first.phone).to eq(phone)
      end
    end

    it 'finds Users interested in a Recall' do
      users = User.has_interest_in_recall(@food_west)
      expect(users.count).to eq(15)
      users.each do |u|
        expect((u.audience & @food_west.audience).length).to be >= 1
        expect((u.categories & @food_west.categories).length).to be >= 1
        expect((u.distribution & @food_west.distribution).length).to be >= 1
        expect(u).to be_is_member
      end

      users = User.has_interest_in_recall(@professional)
      expect(users.count).to eq(3)
      users.each do |u|
        expect((u.audience & @professional.audience).length).to be >= 1
        expect((u.categories & @professional.categories).length).to be >= 1
        expect((u.distribution & @professional.distribution).length).to be >= 1
        expect(u).to be_is_member
      end

      users = User.has_interest_in_recall(@both)
      expect(users.count).to eq(18)
      users.each do |u|
        expect((u.audience & @both.audience).length).to be >= 1 unless u.audience.blank?
        expect((u.categories & @both.categories).length).to be >= 1
        expect((u.distribution & @both.distribution).length).to be >= 1
        expect(u).to be_is_member
      end

      users = User.has_interest_in_recall(@toys_nationwide)
      expect(users.count).to eq(3)
      users.each do |u|
        expect((u.audience & @toys_nationwide.audience).length).to be >= 1
        expect((u.categories & @toys_nationwide.categories).length).to be >= 1
        expect((u.distribution & @toys_nationwide.distribution).length).to be >= 1
        expect(u).to be_is_member
      end

      users = User.has_interest_in_recall(@carseats_nationwide)
      expect(users.count).to eq(7)
      users.each do |u|
        expect((u.audience & @carseats_nationwide.audience).length).to be >= 1
        expect((u.categories & @carseats_nationwide.categories).length).to be >= 1
        expect((u.distribution & @carseats_nationwide.distribution).length).to be >= 1
        expect(u).to be_is_member
      end
    end

    it 'returns no Users for an uninteresting Recall' do
      users = User.has_interest_in_recall(@uninteresting_southeast)
      expect(users.count).to eq(0)
    end

    it 'finds Users desiring an alert by email for a recall' do
      users = User.wants_recall_email_alert(@food_west)
      expect(users.count).to eq(8)

      count_by_email = 0
      users.each do |u|
        count_by_email += 1 if u.alert_by_email?
        expect(u).to be_is_member
      end
      expect(count_by_email).to eq(8)
    end

    it 'finds Users desiring recall summaries' do
      users = User.wants_recall_summary
      expect(users.count).to eq(20)

      count_summaries = 0
      users.each do |u|
        count_summaries += 1 if u.send_summaries?
        expect(u).to be_is_member
      end
      expect(count_summaries).to eq(20)
    end

    it 'finds Users desiring a vehicle alert by email' do
      users = User.wants_vehicle_email_alert(@vehicle_recall.vkeys)
      expect(users.count).to eq(5)

      count_by_email = 0
      users.each do |u|
        count_by_email += 1 if u.alert_for_vins?
        expect(u).to be_is_member
      end
      expect(count_by_email).to eq(5)
    end

    it 'finds Users desiring vehicle summaries' do
      users = User.wants_vehicle_summary
      expect(users.count).to eq(17)

      count_summaries = 0
      users.each do |u|
        count_summaries += 1 if u.send_vin_summaries?
        expect(u).to be_is_member
      end
      expect(count_summaries).to eq(17)
    end

    it 'finds Users in the requested roles' do
      users = User.in_roles('admin', 'member')
      expect(users.count).to eq(37)

      users.each do |u|
        expect(['admin', 'member']).to include(u.role)
      end
    end

    it 'finds Users who are admins' do
      users = User.is_admin
      expect(users.count).to eq(1)

      users.each do |u|
        expect(u.role).to eq('admin')
      end
    end

    it 'finds Users who are workers' do
      users = User.is_worker
      expect(users.count).to eq(1)

      users.each do |u|
        expect(u.role).to eq('worker')
      end
    end

    it 'finds Users who are members' do
      users = User.is_member
      expect(users.count).to eq(37)

      users.each do |u|
        expect(u.role).to eq('member')
      end
    end

    it 'finds the User with a specific customer identifier' do
      user = User.all.detect{|u| u.customer_id.present?}
      expect(user.customer_id).to be_present
      expect(User.with_customer(user.customer_id).first).to eq(user)
    end

    it 'returns users with subscriptions expiring on or after a date' do
      date = @now + 1.year + 1.day 
      users = User.with_subscription_expiring_after(date)
      expect(users.count).to eq(20)
      users.each do |u|
        expect(u.subscriptions.first.expires_on).to be >= date
      end
    end

    it 'returns users with subscriptions expiring on or before a date' do
      date = @now + 1.year + 1.day
      users = User.with_subscription_expiring_before(date)
      expect(users.count).to eq(16)
      users.each do |u|
        expect(u.subscriptions.first.expires_on).to be <= date
      end
    end

    it 'returns users with subscriptions expiring during a date range' do
      t1 = @now + 6.months - 1.day
      t2 = t1 + 2.days
      users = User.with_subscription_expiring_during(t1, t2)
      expect(users.count).to eq(3)
      users.each do |u|
        expect(u.subscriptions.first.expires_on).to be >= t1
        expect(u.subscriptions.first.expires_on).to be <= t2
      end
    end

    it 'returns users whose subscriptions expire on a date' do
      date = @now + 1.year
      users = User.with_subscription_expiring_on(date)
      expect(users.count).to eq(7)
      users.each do |u|
        expect(u.subscriptions.first.expires_on).to be >= date.beginning_of_day
        expect(u.subscriptions.first.expires_on).to be <= date.end_of_day
      end
    end

    it 'finds Users with an subscription' do
      users = User.has_active_subscription
      expect(users.count).to eq(30)
      users.each do |u|
        expect(u).to be_active
      end
    end

    it 'finds Users with an active recall subscription' do
      users = User.has_recall_subscription
      expect(users.count).to eq(25)
      users.each do |u|
        expect(u).to be_has_recall_subscription
      end
    end

    it 'finds Users with an active VIN subscription' do
      users = User.has_vehicle_subscription
      expect(users.count).to eq(22)
      users.each do |u|
        expect(u).to be_has_vehicle_subscription
      end
    end

    it 'finds the User owning a given subscription' do
      users = User.has_active_subscription
      users.each do |u|
        u.subscriptions.each do |s|
          uu = User.owns_subscription(s)
          expect(uu.count).to eq(1)
          expect(u.id).to eq(uu.first.id)
        end
      end
    end

    it 'finds the User owning a given VIN' do
      users = User.has_vehicle_subscription
      users.each do |u|
        u.subscriptions.each do |s|
          s.vins.each do |v|
            uu = User.owns_vin(v)
            expect(uu.count).to eq(1)
            expect(u.id).to eq(uu.first.id)
          end
        end
      end
    end

    it 'finds User who are inactive' do
      users = User.is_inactive
      expect(users.count).to eq(6)
      users.each do |u|
        expect(u).to be_is_member
        expect(u).to be_inactive
      end
    end

    it 'finds all Users interested in a vkey' do
      vkeys = {}
      vkey_users = 0
      User.all.each do |u|
        next unless u.is_member? && u.has_vehicle_subscription?
        vkey_users += 1
        u.subscriptions.first.vkeys.each do |vkey|
          vkeys[vkey] = 0 unless vkeys.has_key?(vkey)
          vkeys[vkey] += 1
        end
      end

      vkeys.each do |vkey, expected_count|
        users = User.has_interest_in_vkey(vkey)
        expect(users.count).to eq(expected_count)
        users.each do |u|
          expect(u).to be_has_vehicle_subscription
          expect(u.subscriptions.first.vkeys).to be_include(vkey)
          expect(u).to be_is_member
        end
      end
    end

    it 'finds all users interested in multiple vkeys' do
      vkeys = []
      vkey_users = 0
      User.all.each do |u|
        next unless u.is_member? && u.has_vehicle_subscription?
        vkeys += u.vins.map{|v| v.to_vkey }
        vkey_users += 1
      end
      vkeys = vkeys.uniq

      expect(User.has_interest_in_vkey(vkeys).count).to eq(vkey_users)
    end

    it 'finds all Users not interested in a vkey' do
      TestConstants::UNKNOWN_VKEYS.each do |vkey|
        expect(User.has_no_interest_in_vkey(vkey).count).to eq(User.has_vehicle_subscription.count)
      end
    end

    it 'finds all Users not interested in multiple vkeys' do
      expect(User.has_no_interest_in_vkey(TestConstants::UNKNOWN_VKEYS).count).to eq(User.has_vehicle_subscription.count)
    end

    it 'finds Users with unreviewed VINs' do
      users = User.has_unreviewed_vin
      expect(users.count).to eq(7)
      users.each do |u|
        expect(u.unreviewed_vins.length).to be > 0
        expect(u).to be_is_member
      end
    end

  end

  context 'Preference Validation' do

    before :example do
      @u = build(:user)
      @p = @u.preference
    end

    after :example do
      User.destroy_all
    end

    it 'validates' do
      expect(@p).to be_valid
    end

    it 'accepts alerts by email' do
      @p.alert_by_email!
      expect(@p).to be_alert_by_email
      expect(@p).to be_valid
    end

    it 'does not require alerts by email' do
      @p.alert_by_email!(false)
      expect(@p).to_not be_alert_by_email
      expect(@p).to be_valid
    end

    it 'accepts alerts by phone' do
      @p.alert_by_phone!
      expect(@p).to be_alert_by_phone
      expect(@p).to be_valid
    end

    it 'does not require alerts by phone' do
      @p.alert_by_phone!(false)
      expect(@p).to_not be_alert_by_phone
      expect(@p).to be_valid
    end
    
    it 'does not require any audience' do
      @p.audience = nil
      expect(@p).to be_valid
    end

    it 'accepts just one audience' do
      @p.audience = FeedConstants::AUDIENCE.first
      expect(@p).to be_valid
    end

    it 'allows multiple audiences' do
      @p.audience = FeedConstants::AUDIENCE
      expect(@p).to be_valid
    end

    it 'rejects unrecognized audience values' do
      @p.audience = ['not a audience', 'another not a audience']
      expect(@p).to be_invalid
      expect(@p.errors).to have_key(:audience)
    end

    it 'removes duplicate audience values' do
      @p.audience = FeedConstants::AUDIENCE + FeedConstants::AUDIENCE
      expect(@p).to be_valid
      expect(@p.audience).to match_array(FeedConstants::AUDIENCE)
    end

    it 'does not require any categories' do
      @p.categories = nil
      expect(@p).to be_valid
    end

    it 'accepts just one category' do
      @p.categories = 'food'
      expect(@p).to be_valid
    end

    it 'allows categories from one source' do
      @p.categories = FeedConstants::FDA_CATEGORIES
      expect(@p).to be_valid
    end

    it 'allows categories from multiple sources' do
      @p.categories = FeedConstants::PUBLIC_CATEGORIES
      expect(@p).to be_valid
    end

    it 'rejects unrecognized category values' do
      @p.categories = ['not a category', 'another not a category']
      expect(@p).to be_invalid
      expect(@p.errors).to have_key(:categories)
    end

    it 'removes duplicate category values' do
      @p.categories = FeedConstants::FDA_CATEGORIES + FeedConstants::FDA_CATEGORIES
      expect(@p).to be_valid
      expect(@p.categories).to match_array(FeedConstants::FDA_CATEGORIES)
    end

    it 'does not require a distribution' do
      @p.distribution = nil
      expect(@p).to be_valid
    end

    it 'accepts a selection of states for the distribution' do
      @p.distribution = USRegions::REGIONS[:west] + USRegions::COASTS[:east]
      expect(@p).to be_valid
    end

    it 'rejects unrecognized states for the distribution' do
      @p.distribution = ['Seattle', 'Portland']
      expect(@p).to be_invalid
      expect(@p.errors).to have_key(:distribution)
    end

    it 'removes duplicate distribution values' do
      @p.distribution = USRegions::REGIONS[:west] + USRegions::COASTS[:west]
      expect(@p).to be_valid
      expect(@p.distribution).to match_array(USRegions::REGIONS[:west])
    end

    it 'does not require a risk' do
      @p.risk = nil
      expect(@p).to be_valid
    end

    it 'accepts a selection of risk values' do
      FeedConstants::RISK.each do |ri|
        @p.risk = ri
        expect(@p).to be_valid
      end

      @p.risk = ['probable', 'possible']
      expect(@p).to be_valid

      @p.risk = ['probable', 'none']
      expect(@p).to be_valid

      @p.risk = ['possible', 'none']
      expect(@p).to be_valid

      @p.risk = ['probable', 'possible', 'none']
      expect(@p).to be_valid
    end

    it 'removes duplicate risk values' do
      @p.risk =['probable', 'possible', 'probable']
      expect(@p).to be_valid
      expect(@p.risk).to match_array(['probable', 'possible'])
    end

  end

  context 'Preference Behavior' do

    before :each do
      @preference = build(:preference,
        alert_by_email: true, 
        alert_by_phone: true,
        send_summaries: true,
        audience: ['professionals'],
        categories: FeedConstants::FDA_CATEGORIES,
        distribution: USRegions::COASTS[:west])
      @user = build(:user, phone: '123.446.7890', preference: @preference)
    end

    after :each do
      User.destroy_all
    end

    it 'returns the Preference alert by email value' do
      expect(@user).to be_valid
      expect(@preference).to be_alert_by_email
      expect(@user).to be_alert_by_email
    end

    it 'sets the Preference alert by email value' do
      expect(@user).to be_valid
      @user.alert_by_email!(false)
      expect(@preference).to_not be_alert_by_email
      expect(@user).to_not be_alert_by_email
    end

    it 'returns the Preference alert by phone value' do
      expect(@user).to be_valid
      expect(@preference).to be_alert_by_phone
      expect(@user).to be_alert_by_phone
    end

    it 'sets the Preference alert by phone value' do
      expect(@user).to be_valid
      @user.alert_by_phone!(false)
      expect(@preference).to_not be_alert_by_phone
      expect(@user).to_not be_alert_by_phone
    end

    it 'returns the Preference send summaries value' do
      expect(@user).to be_valid
      expect(@preference).to be_send_summaries
      expect(@user).to be_send_summaries
    end

    it 'sets the Preference weekly summaries value' do
      expect(@user).to be_valid
      @user.send_summaries!(false)
      expect(@preference).to_not be_send_summaries
      expect(@user).to_not be_send_summaries
    end

    it 'returns the Preference alert for vins value' do
      expect(@user).to be_valid
      expect(@preference).to be_alert_for_vins
      expect(@user).to be_alert_for_vins
    end

    it 'sets the Preference alert for vins value' do
      expect(@user).to be_valid
      @user.alert_for_vins!(false)
      expect(@preference).to_not be_alert_for_vins
      expect(@user).to_not be_alert_for_vins
    end

    it 'returns the Preference send vin summaries value' do
      expect(@user).to be_valid
      expect(@preference).to be_send_vin_summaries
      expect(@user).to be_send_vin_summaries
    end

    it 'sets the Preference send vin summaries value' do
      expect(@user).to be_valid
      @user.send_vin_summaries!(false)
      expect(@preference).to_not be_send_vin_summaries
      expect(@user).to_not be_send_vin_summaries
    end

    it 'returns the Preference audience' do
      expect(@user).to be_valid
      expect(@user.audience).to match_array(@preference.audience)
    end

    it 'returns the Preference categories' do
      expect(@user).to be_valid
      expect(@user.categories).to match_array(@preference.categories)
    end

    it 'returns the Preference distribution' do
      expect(@user).to be_valid
      expect(@user.distribution).to match_array(@preference.distribution)
    end

    it 'returns the Preference risk' do
      expect(@user).to be_valid
      expect(@user.risk).to match_array(@preference.risk)
    end

    it 'ensures the Preference audience field is never empty' do
      @user.preference.audience = nil
      expect(@user).to be_valid
      expect(@user.preference.audience).to match_array(FeedConstants::DEFAULT_AUDIENCE)

      @user.preference.audience = []
      expect(@user).to be_valid
      expect(@user.preference.audience).to match_array(FeedConstants::DEFAULT_AUDIENCE)
    end

    it 'ensures the Preference categories field is never empty' do
      @user.preference.categories = nil
      expect(@user).to be_valid
      expect(@user.preference.categories).to match_array(FeedConstants::DEFAULT_CATEGORIES)

      @user.preference.categories = []
      expect(@user).to be_valid
      expect(@user.preference.categories).to match_array(FeedConstants::DEFAULT_CATEGORIES)
    end

    it 'ensures the Preference distribution field is never empty' do
      @user.preference.distribution = nil
      expect(@user).to be_valid
      expect(@user.preference.distribution).to match_array(USRegions::STATES)

      @user.preference.distribution = []
      expect(@user).to be_valid
      expect(@user.preference.distribution).to match_array(USRegions::STATES)
    end

    it 'ensures the Preference risk field is never empty' do
      @user.preference.risk = nil
      expect(@user).to be_valid
      expect(@user.preference.risk).to match_array(FeedConstants::DEFAULT_RISK)

      @user.preference.risk = []
      expect(@user).to be_valid
      expect(@user.preference.risk).to match_array(FeedConstants::DEFAULT_RISK)
    end

  end

  context 'Subscription Validation' do

    before :example do
      @u = build(:user, count_subscriptions: 1)
      expect(@u.subscriptions.length).to eq(1)
      @s = @u.subscriptions.first
    end

    after :example do
      User.destroy_all
    end

    it 'validates' do
      expect(@s).to be_valid
    end

    it 'requires a start date' do
      @s.started_on = ''
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:started_on)

      @s.started_on = nil
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:started_on)
    end

    it 'requires a renews date' do
      @s.renews_on = ''
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:renews_on)

      @s.renews_on = nil
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:renews_on)
    end

    it 'requires the start date to come on or before the renews date' do
      @s.started_on = @s.renews_on + 1.day
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:started_on)
    end

    it 'requires an expiration date' do
      @s.expires_on = ''
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:expires_on)

      @s.expires_on = nil
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:expires_on)
    end

    it 'allows past expiration dates' do
      @s.expires_on = 1.year.ago
      expect(@s).to be_valid
    end

    it 'allows future expiration dates' do
      @s.expires_on = 1.year.from_now
      expect(@s).to be_valid
    end

    it 'requires a status' do
      @s.status = ''
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:status)

      @s.status = nil
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:status)
    end

    it 'accepts all valid status values' do
      Subscription::STATUS.each do |status|
        @s.status = status
        expect(@s).to be_valid
      end
    end

    it 'rejects an unknown status' do
      @s.status = 'notastatus'
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:status)
    end

    it 'requires a stripe identifier' do
      @s.stripe_id = ''
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:stripe_id)

      @s.stripe_id = nil
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:stripe_id)
    end

    it 'requires a plan identifier' do
      @s.plan_id = ''
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:plan_id)

      @s.plan_id = nil
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:plan_id)
    end

    it 'accepts valid plan identifiers' do
      Plan.all.each do |plan|
        @s.plan_id = plan.id
        expect(@s).to be_valid
      end
    end

    it 'rejects invalid plan indentifiers' do
      @s.plan_id = 'not a plan'
      expect(@s).to be_invalid
      expect(@s.errors).to have_key(:plan_id)
    end

    it 'promotes plan attributes on new records' do
      expect(@s).to be_new_record
      @s.recalls = nil
      @s.count_vins = nil

      plan = Plan.from_id(@s.plan_id)
      expect(plan).to be_instance_of(Plan)
      expect(@s).to be_valid
      expect(@s.recalls).to eq(plan.recalls)
      expect(@s.count_vins).to eq(plan.vins)
    end

    it 'does not promote plan attributes unless the plan changed' do
      expect(@s.plan_id).to eq(Plan.yearly_all.id)

      @s.save!
      expect(@s.recalls).to be true

      @s.recalls = false
      @s.save!
      expect(@s.recalls).to be false
    end

    it 'does promote plan attributes if the plan changed' do
      expect(@s.plan_id).to eq(Plan.yearly_all.id)

      @s.save!
      expect(@s.recalls).to be true

      @s.plan_id = Plan.yearly_vins.id
      @s.save!
      expect(@s.recalls).to be false
    end

    it 'does not require vins' do
      @s.save!

      @s.vins = nil
      expect(@s).to be_valid

      @s.vins = []
      expect(@s).to be_valid
    end

    it 'creates empty VINs' do
      expect(@s.plan_id).to eq(Plan.yearly_all.id)
      @s.vins = []
      expect(@s.vins).to be_blank

      expect(@s).to be_valid
      expect(@s.count_vins).to be > 0
      expect(@s.vins.length).to eq(@s.count_vins)
      @s.vins.each do |v|
        expect(v.vin).to be_blank
      end
    end

    it 'rejects non-integer VIN counts' do
      @s.save!
      @s.count_vins = 4.2
      expect(@s).to_not be_valid
      expect(@s.errors).to have_key(:count_vins)
    end

    it 'rejects VIN counts less than 0' do
      @s.save!
      @s.count_vins = -1
      expect(@s).to_not be_valid
      expect(@s.errors).to have_key(:count_vins)
    end

    it 'accepts a VIN count of 0' do
      @s.save!
      @s.count_vins = 0
      expect(@s).to be_valid
    end

    it 'accepts VIN counts greater than 0' do
      @s.save!
      @s.count_vins = 42
      expect(@s).to be_valid
    end

    it 'populates vkeys before validation' do
      expect(@s.vkeys).to be_blank
      expect(@s).to be_valid
      expect(@s.vkeys).to be_present
    end

    it 'will merge errors from the nested vins' do
      @s.vins.first.vin = 'notavalidvin'

      expect(@s).to_not be_valid
      expect(@s.merged_errors.full_messages.first).to start_with('Vin notavalidvin is not ')
    end

    it 'will merge errors from the nested vin vehicle' do
      @s.vins.first.vehicle.year = Time.now.year + Vehicle::MAXIMUM_YEARS_HENCE + 1

      expect(@s).to_not be_valid
      expect(@s.merged_errors.full_messages.first).to start_with('Vin vehicle year ')
    end

  end

  context 'Subscription Behavior' do

    before :each do
      @u = create(:user, count_subscriptions: 3)

      # Expire the initial recalls subscription
      s = @u.subscriptions.first
      s.started_on = 3.years.ago
      s.renews_on =
      s.expires_on = 2.years.ago

      @u.subscriptions << build(:subscription, stripe_id: 'recalls_subscription', plan: Plan.yearly_recalls)
      @u.save!

      expect(@u.subscriptions.length).to eq(4)
      expect(@u.active_subscriptions.length).to eq(3)

      @s = @u.recall_subscription
      expect(@s).to be_active
      expect(@s).to be_for_plan(Plan.yearly_recalls)

      @stripe = Stripe::Subscription.construct_from(load_stripe('recalls_subscription.json'))
    end

    after :each do
      User.destroy_all
    end

    it 'disallows subscribing to multiple recall plans' do
      expect(@u).to be_has_recall_subscription
      Plan.all.each do |plan|
        next unless plan.for_recalls?
        expect(@u).to_not be_can_subscribe_to(plan)
      end
    end

    it 'allows multiple vehicle subscriptions' do
      expect(@u).to be_has_recall_subscription
      Plan.all.each do |plan|
        next if plan.for_recalls?
        expect(@u).to be_can_subscribe_to(plan)
      end
    end

    it 'creates a subscription from a Stripe subscription' do
      s = Subscription.build_from_stripe(@stripe)
      expect(s.stripe_id).to eq(@stripe.id)
      expect(s.plan_id).to eq(@stripe.plan.id)
      expect(s.started_on).to eq(Time.at(@stripe.start_date).beginning_of_day.beginning_of_minute.utc)
      expect(s.renews_on).to eq(Time.at(@stripe.current_period_end).end_of_day.beginning_of_minute.utc)
      expect(s.expires_on).to eq(Constants::FAR_FUTURE.start_of_grace_period)
      expect(s).to be_active
    end

    it 'synchronizes with Stripe' do
      s = @u.synchronize_stripe!(@stripe)
      expect(s).to be_present
      expect(s).to be_is_a(Subscription)

      expect(s.id).to eq(@s.id)
      expect(s.stripe_id).to eq(@stripe.id)
      expect(s.plan_id).to eq(@stripe.plan.id)
      expect(s.started_on).to eq(Time.at(@stripe.start_date).beginning_of_day.beginning_of_minute.utc)
      expect(s.renews_on).to eq(Time.at(@stripe.current_period_end).end_of_day.beginning_of_minute.utc)
      expect(s.expires_on).to eq(Constants::FAR_FUTURE.start_of_grace_period)
    end

    it 'returns nil if it cannot acquire the lock' do
      expect(@u).to receive(:with_lock).and_raise(Mongoid::Locker::Errors::DocumentCouldNotGetLock.new(User, @u.id))
      expect(@u.synchronize_stripe!(@stripe)).to be_nil
    end

    it 'requires a customer identifier when subscribed' do
      @u.customer_id = ''
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:customer_id)

      @u.customer_id = nil
      expect(@u).to be_invalid
      expect(@u.errors).to have_key(:customer_id)
    end

    it 'does not require a customer identifier when not subscribed' do
      @u.subscriptions.clear

      @u.customer_id = ''
      expect(@u).to be_valid

      @u.customer_id = nil
      expect(@u).to be_valid
    end

    it 'returns the active plans' do
      p = @u.active_plans
      expect(p.length).to eq(2)
      expect(p).to be_include(Plan.yearly_recalls)
      expect(p).to be_include(Plan.yearly_vins)
    end

    it 'returns the active subscriptions' do
      expect(@u.active_subscriptions.length).to eq(3)
    end

    it 'returns the active recall subscription' do
      expect(@u.recall_subscription).to eq(@s)
    end

    it 'returns all active vin subscriptions' do
      ss = @u.vin_subscriptions
      expect(ss.length).to eq(2)
      ss.each do |s|
        expect(s).to be_vins
      end
    end

    it 'returns nil if the recall subscription is expired' do
      expire_at(@s)
      @u.save!
      travel_to 2.years.from_now do
        expect(@u.recall_subscription).to be_blank
      end
    end

    it 'detects users with an active recall subscription' do
      expect(@s).to be_recalls
      expect(@u).to be_has_recall_subscription
    end

    it 'detects users with an active vehicle subscription' do
      s = @u.subscriptions_for_plan(Plan.yearly_vins).first
      expect(s.vins).to be_present
      expect(@u).to be_has_vehicle_subscription
    end

    it 'detects inactive users' do
      expire_all!(@u)
      travel_to 2.years.from_now do
        expect(@s).to_not be_active
        expect(@u).to be_inactive
      end
    end

    it 'treats users with no subscriptions as inactive' do
      reset_subscriptions!(@u)
      expect(@u).to be_inactive
    end

    it 'acknowledges subscribed plans' do
      @u.subscriptions.each do |s|
        next unless s.active?
        expect(@u).to be_subscribed_to(s.plan_id)
        expect(@u).to be_subscribed_to(Plan.from_id(s.plan_id))
      end
    end

    it 'disavows unknown plans' do
      expect(@u).to_not be_subscribed_to('notaplan')
    end

    it 'disavows expired plans' do
      expire_all!(@u)
      travel_to 2.years.from_now do
        @u.subscriptions.each do |s|
          expect(@u).to_not be_subscribed_to(s.plan_id)
        end
      end
    end

    it 'synchronizes the customer account when the email is changed' do
      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))

      expect(Stripe::Customer).to receive(:retrieve).and_return(customer)
      expect(customer).to receive(:save).and_return({})

      @u.email = 'new_email@nomail.com'
      @u.customer_id = customer.id
      @u.save!

      expect(customer.email).to eq('new_email@nomail.com')
    end

    it 'does not synchronize the customer if the email has not changed' do
      customer = Stripe::Customer.construct_from(load_stripe('customer.json'))

      expect(Stripe::Customer).to_not receive(:retrieve)

      @u.customer_id = customer.id
      @u.save!
    end

    it 'acknowledges an active subscription' do
      expect(@s).to be_active
    end

    it 'acknowledges an inactive subscription' do
      expect(@s).to be_inactive(@s.expires_on.end_of_grace_period + 1.second)
    end

    it 'returns a expiration with a grace period' do
      expect(@s.expiration).to eq(@s.expires_on.end_of_grace_period)
    end

    it 'acknowledges if it is for a plan' do
      expect(@s).to be_for_plan(@s.plan_id)
      expect(@s).to be_for_plan(Plan.from_id(@s.plan_id))
    end

    it 'disavows unknown plans' do
      expect(@s).to_not be_for_plan('notaplan')
    end

    it 'acknowledges if it is for the Stripe identifier' do
      expect(@s).to be_for_stripe_id(@s.stripe_id)
    end

    it 'disavows unknown Stripe identifiers' do
      expect(@s).to_not be_for_stripe_id('notastripeidentifier')
    end

    it 'returns all plans for the active subscriptions' do
      plans = @u.active_plans
      plan_ids = plans.map{|p| p.id}
      @u.subscriptions.each do |s|
        next unless s.active?
        expect(plan_ids).to be_include(s.plan_id)
      end
    end

    it 'returns only plans for the active subscriptions' do
      plans = @u.active_plans
      plan_ids = plans.map{|p| p.id}
      @u.subscriptions.each do |s|
        next if s.active?
        expect(plan_ids).to_not be_include(s.plan_id)
      end
    end

    it 'returns each plans only once' do
      plans = @u.active_plans
      plan_ids = plans.map{|p| p.id}
      expect(plan_ids.length).to eq(plan_ids.uniq.length)
    end

    it 'locates vins by id' do
      s = @u.subscriptions_for_plan(Plan.yearly_vins).first
      expect(s.vins.length).to be > 1
      s.vins.each do |v|
        expect(s.vin_from_id(v.id)).to eq(v)
      end
    end

  end

  context 'Vin Validation' do

    before :example do
      @u = build(:user, count_subscriptions: 1)
      expect(@u.subscriptions.length).to eq(1)
      @s = @u.subscriptions.first
      @v = @s.vins.first
    end

    after :example do
      User.destroy_all
    end

    it 'validates' do
      expect(@v).to be_valid
    end

    it 'does not require a vin' do
      @v.vin = ''
      expect(@v).to be_valid

      @v.vin = nil
      expect(@v).to be_valid
    end

    it 'requires a valid vin' do
      @v.vin = 'abadvin'
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:base)
    end

    it 'requires the vehicle to be set if the VIN is set' do
      @v.vehicle.reset
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:base)
    end

    it 'requires a vehicle if the VIN is set' do
      @v.vehicle = nil
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:base)
    end

    it 'rejects a set vehicle if the VIN is missing' do
      va = @v.vehicle.attributes.dup

      @v.vin = ''
      @v.vehicle = Vehicle.new(va)
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:base)

      @v.vin = nil
      @v.vehicle = Vehicle.new(va)
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:base)
    end

    it 'rejects a set vehicle if the VIN is invalid' do
      va = @v.vehicle.attributes.dup

      @v.vin = 'abadvin'
      @v.vehicle = Vehicle.new(va)
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:base)
    end

    it 'accepts an empty array of campaigns' do
      expect(@v.campaigns).to be_blank
      expect(@v).to be_valid
    end

    it 'accepts NHTSA campaign identifiers for campaigns' do
      @v.campaigns = select_from(TestConstants::CAMPAIGNS, Helper.rand(9))
      expect(@v).to be_valid
    end

    it 'rejects values other than NHTSA campaign identifiers for campaigns' do
      @v.campaigns = ['notacampaignid']
      expect(@v).to_not be_valid
      expect(@v.errors).to have_key(:campaigns)

      @v.campaigns = [42]
      expect(@v).to_not be_valid
      expect(@v.errors).to have_key(:campaigns)
    end

    it 'rejects any campaign value if the VIN is missing' do
      @v.vin = nil
      @v.campaigns = select_from(TestConstants::CAMPAIGNS, Helper.rand(9))
      expect(@v).to_not be_valid
      expect(@v.errors).to have_key(:campaigns)
    end

    it 'will merge errors from the nested vehicles' do
      @v.vehicle.year = Time.now.year + Vehicle::MAXIMUM_YEARS_HENCE + 1

      expect(@v).to_not be_valid
      expect(@v.merged_errors.full_messages.first).to start_with('Vehicle year ')
    end

  end

  context 'Vin Behavior' do

    before :each do
      @u = create(:user, count_subscriptions: 4)
      expire_at(@u.subscriptions.last, 1.month.ago)
      @u.save!

      expect(@u.subscriptions.length).to eq(4)
      @s = @u.subscriptions.first

      expect(@s.vins).to be_present
      @v = @s.vins.first
    end

    after :each do
      User.destroy_all
    end

    it 'clears the make, model, and year when the VIN is cleared' do
      expect(@v.vehicle).to_not be_blank

      @v.vin = nil
      expect(@v.vehicle).to be_blank
    end

    it 'returns nil for the vkey when the VIN is absent' do
      @v.vin = nil
      expect(@v.to_vkey).to be_nil
    end

    it 'acknowledges that updates are allowed if there was no prior VIN' do
      @u.subscriptions.clear

      @s = build(:subscription, count_vins: 0)
      @s.vins = build_list(:vin, @s.count_vins, vin: nil)
      @u.subscriptions << @s
      @u.save!

      @v = @s.vins.first
      expect(@v).to be_allow_updates
    end

    it 'returns all the vins from active the subscriptions' do
      v = []
      @u.subscriptions.each{|s| v << s.vins if s.active?}
      v.flatten!

      vins = @u.vins
      expect(vins.length).to eq(@u.subscriptions.sum{|s| s.active? ? s.vins.length : 0})
      expect(vins).to match(v)
    end

    it 'returns all the vins from all the subscriptions' do
      v = []
      @u.subscriptions.each{|s| v << s.vins}
      v.flatten!

      vins = @u.vins(true)
      expect(vins.length).to eq(@u.subscriptions.sum{|s| s.vins.length})
      expect(vins).to match(v)
    end

  end

  context 'Vehicle Validation' do

    before :example do
      @u = build(:user, count_subscriptions: 1)
      expect(@u.subscriptions.length).to eq(1)
      @s = @u.subscriptions.first
      @v = @s.vins.first.vehicle
    end

    after :example do
      User.destroy_all
    end

    it 'validates' do
      expect(@v).to be_valid
    end

    it 'requires a make if model is present' do
      @v.year = nil
      expect(@v.model).to be_present

      @v.make = ''
      expect(@v).to be_invalid

      @v.make = nil
      expect(@v).to be_invalid
    end

    it 'requires a make if year is present' do
      @v.model = nil
      expect(@v.year).to be_present

      @v.make = ''
      expect(@v).to be_invalid

      @v.make = nil
      expect(@v).to be_invalid
    end

    it 'requires a model if make is present' do
      @v.year = nil
      expect(@v.model).to be_present

      @v.model = ''
      expect(@v).to be_invalid

      @v.model = nil
      expect(@v).to be_invalid
    end

    it 'requires a model if year is present' do
      @v.make = nil
      expect(@v.year).to be_present

      @v.model = ''
      expect(@v).to be_invalid

      @v.model = nil
      expect(@v).to be_invalid
    end

    it 'requires a year if make is present' do
      @v.model = nil
      expect(@v.make).to be_present

      @v.year = nil
      expect(@v).to be_invalid
    end

    it 'requires a year if model is present' do
      @v.make = nil
      expect(@v.model).to be_present

      @v.year = nil
      expect(@v).to be_invalid
    end

    it "requires a year after #{Constants::MINIMUM_VEHICLE_YEAR}" do
      @v.year = Constants::MINIMUM_VEHICLE_YEAR - 1
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:year)
    end

    it "allows the year to up to #{Vehicle::MAXIMUM_YEARS_HENCE} years in the future" do
      (1..Vehicle::MAXIMUM_YEARS_HENCE).each do |i|
        @v.year = Time.now.year + i
        expect(@v).to be_valid
      end
    end

    it "disallows years more than #{Vehicle::MAXIMUM_YEARS_HENCE} years hence" do
      @v.year = Time.now.year + Vehicle::MAXIMUM_YEARS_HENCE + 1
      expect(@v).to be_invalid
      expect(@v.errors).to have_key(:year)
    end

  end

  context 'Vehicle Behavior' do

    before :example do
      @u = build(:user, count_subscriptions: 1)
      expect(@u.subscriptions.length).to eq(1)
      @s = @u.subscriptions.first
      @v = @s.vins.first.vehicle
    end

    after :example do
      User.destroy_all
    end

    it 'returns true for empty vehicles' do
      @v.make =
      @v.model =
      @v.year = nil
      expect(@v).to be_blank
    end

    it 'resetting empties the vehicle' do
      expect(@v).to be_present

      @v.reset
      expect(@v).to be_blank
    end

    it 'returns its vkey' do
      expect(@v.to_vkey).to eq(Vehicles.generate_vkey(@v.make, @v.model, @v.year))
    end

    it 'returns nil for non-existent vehicles' do
      @v.make =
      @v.model =
      @v.year = nil
      expect(@v.to_vkey).to be_nil
    end

  end

end
