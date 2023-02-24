require 'rails_helper'
include ActiveJob::TestHelper

describe 'User Management', type: :request do

  describe 'Retrieving / searching Users' do

    before :all do
      @users = []
      @inactive_users = []
      @recall_users = []
      @vehicle_users = []

      freeze_time do
        @now = Time.now

        @admin = create(:admin)
        @admin.refresh_access_token!

        @worker = create(:worker)
        @worker.refresh_access_token!


        # Create guest user
        # - This user should never appear in any results
        User.guest_user

        p = build(:preference,
          audience: FeedConstants::DEFAULT_AUDIENCE,
          categories: ['food'],
          distribution: USRegions::REGIONS[:nationwide],
          risk: ['probable', 'possible'],
          alert_by_email: true,
          send_summaries: false)
        (Constants::MAXIMUM_PAGE_SIZE).times do
          @recall_users << create(:user,
            created_at: 1.month.ago,
            phone: '123.456.7890',
            preference: p,
            plan: Plan.yearly_recalls)
        end

        p = build(:preference,
          audience: FeedConstants::DEFAULT_AUDIENCE,
          categories: ['food'],
          distribution: USRegions::REGIONS[:nationwide],
          risk: ['probable', 'possible'],
          alert_by_email: false,
          send_summaries: true)
        (Constants::MAXIMUM_PAGE_SIZE).times do
          @recall_users << create(:user,
            created_at: 3.weeks.ago,
            phone: '123.456.7890',
            preference: p,
            plan: Plan.yearly_recalls)
        end
        @users += @recall_users

        p = build(:preference,
          audience: FeedConstants::DEFAULT_AUDIENCE,
          categories: ['personal'],
          distribution: USRegions::REGIONS[:nationwide],
          risk: ['probable', 'possible'],
          alert_for_vins: true,
          send_vin_summaries: true,
          alert_by_email: true,
          send_summaries: true)
        (Constants::MAXIMUM_PAGE_SIZE * 2).times do
          @inactive_users << create(:user,
            created_at: 2.weeks.ago,
            phone: '123.456.7890',
            preference: p,
            count_subscriptions: 0,
            count_vins: 0)
        end
        @users += @inactive_users

        p = build(:preference,
          audience: FeedConstants::DEFAULT_AUDIENCE,
          categories: ['personal'],
          distribution: USRegions::REGIONS[:nationwide],
          risk: ['probable', 'possible'],
          alert_for_vins: true,
          send_vin_summaries: false,
          alert_by_email: true,
          send_summaries: true)
        (Constants::MAXIMUM_PAGE_SIZE / 2).times do
          @vehicle_users << create(:user,
            created_at: 1.week.ago,
            phone: '123.456.7890',
            preference: p,
            plan: Plan.yearly_vins)
        end

        p = build(:preference,
          audience: FeedConstants::DEFAULT_AUDIENCE,
          categories: ['personal'],
          distribution: USRegions::REGIONS[:nationwide],
          risk: ['probable', 'possible'],
          alert_for_vins: false,
          send_vin_summaries: true,
          alert_by_email: true,
          send_summaries: true)
        (Constants::MAXIMUM_PAGE_SIZE / 2).times do
          @vehicle_users << create(:user,
            created_at: @now,
            phone: '123.456.7890',
            preference: p,
            plan: Plan.yearly_vins)
        end
        @users += @vehicle_users
      end

      expect(User.is_inactive.count).to eq(@inactive_users.length)
      expect(User.has_recall_subscription.count).to eq(@recall_users.length)
      expect(User.has_vehicle_subscription.count).to eq(@vehicle_users.length)

      @users.sort!{|u1, u2| u1.email <=> u2.email }.reverse!
      @users.each{|u| u.email_confirmed!}

      @recall = create(:recall, feed_name: 'fda', categories: ['food'], publication_date: 3.days.ago)
      @uninteresting_recall = create(:recall, feed_name: 'cpsc', categories: ['commercial'], publication_date: 3.days.ago)
      
      vehicles = @vehicle_users.map{|u| u.vins.map{|v| v.vehicle} }.flatten.uniq
      @vehicle = create(:vehicle_recall, vehicles: vehicles, publication_date: 5.days.ago)
      @vkeys = vehicles.map{|v| v.to_vkey}

      vehicles = (0...3).map{ select_vin(exclude_vkeys: @vkeys)}.compact.map{|vin| build(:vehicle, vin: vin)}
      raise Exception.new('Unable to create VehicleRecall for no users') unless vehicles.present?
      @uninteresting_vehicle = create(:vehicle_recall, vehicles: vehicles, publication_date: 5.days.ago)
    end

    after :all do
      VehicleRecall.destroy_all
      Recall.destroy_all
      User.destroy_all
    end

    it 'requires a signed-in user' do
      get '/users'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http unauthorized for normal users' do
      get '/users', headers: auth_headers(@users.first)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for administors' do
      get '/users', headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      get '/users', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns an array of documents' do
      count = 5
      get '/users', params: { limit: count }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      users = User.from_json({ users: json })
      expect(users).to match_array(@users.slice(0, count))
    end

    it 'returns the documents sorted by descending email' do
      count = 5
      get '/users', params: { limit: count }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = User.from_json({ users: json })
      prev_email = 'member99@nomail.com'
      data.each do |u|
        expect(u.email).to be <= prev_email
        prev_email = u.email
      end
    end

    it 'returns the documents sorted by descending email if requested' do
      count = 5
      get '/users', params: { limit: count, sort: 'email' }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = User.from_json({ users: json })
      prev_email = 'member99@nomail.com'
      data.each do |u|
        expect(u.email).to be <= prev_email
        prev_email = u.email
      end
    end

    it 'returns the documents sorted by ascending creation date if requested' do
      count = 5
      get '/users', params: { limit: count, sort: 'created' }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      users = User.from_json({ users: json })
      created_at = 5.years.ago
      users.each do |u|
        expect(u.c_at).to be >= created_at
        created_at = u.c_at
      end
    end

    it 'returns only Users created after a given date' do
      total = 60
      users = fetch_all(:users, User, @admin, total, after: @now-2.weeks)
      expect(users.length).to eq(total)
    end

    it 'returns only Users created before a given date' do
      total = 40
      users = fetch_all(:users, User, @admin, total, before: @now-3.weeks)
      expect(users.length).to eq(total)
    end

    it 'returns a limited-size array of documents' do
      count = 10
      get '/users', params: { limit: count }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      users = User.from_json({ users: json })
      expect(users).to match_array(@users.slice(0, count))
    end

    it 'limits the documents returned to those available' do
      count = [@users.length, Constants::MAXIMUM_PAGE_SIZE].min
      get '/users', params: { limit: count * 42 }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      users = User.from_json({ users: json })
      expect(users).to match_array(@users.slice(0, count))
    end

    it 'returns documents starting at the requested offset' do
      count = 5
      get '/users', params: { limit: count, offset: count }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      users = User.from_json({ users: json })
      expect(users).to match_array(@users.slice(count, count))
    end

    it 'returns no documents if presented with an excessive offset' do
      count = 5
      get '/users', params: { limit: count, offset: @users.length * 42 }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(0)
    end

    it 'limits negative offsets to available documents' do
      count = 5
      get '/users', params: { limit: count, offset: -42 }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      users = User.from_json({ users: json })
      expect(users).to match_array(@users.slice(0, count))
    end

    it 'ignores a passed document total' do
      count = 5
      get '/users', params: { limit: count, offset: @users.length * 42, total: @users.length * 10000 }, headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(0)
    end

    it 'returns only users interested in a specific recall' do
      users = fetch_all(:users, User, @admin, @recall_users.length, recall: @recall.id)
      expect(users).to match_array(@recall_users)
    end

    it 'returns only users interested in a specific recall wanting an alert' do
      total = Constants::MAXIMUM_PAGE_SIZE
      users = fetch_all(:users, User, @admin, total, recall: @recall.id, alert: true)
      expect(users).to match_array(@recall_users.slice(0, total))
    end

    it 'returns no users for an uninteresting recall' do
      users = fetch_all(:users, User, @admin, 0, recall: @uninteresting_recall.id)
      expect(users.length).to eq(0)
    end

    it 'returns only users interested in a specific vehicle recall' do
      users = fetch_all(:users, User, @admin, @vehicle_users.length, vehicle: @vehicle.id)
      expect(users).to match_array(@vehicle_users)
    end

    it 'returns only users interested in a specific vehicle recall wanting an alert' do
      total = Constants::MAXIMUM_PAGE_SIZE / 2
      users = fetch_all(:users, User, @admin, total, vehicle: @vehicle.id, alert: true)
      expect(users).to match_array(@vehicle_users.slice(0, total))
    end

    it 'returns no users for an uninteresting vehicle recall' do
      users = fetch_all(:users, User, @admin, 0, vehicle: @uninteresting_vehicle.id)
      expect(users.length).to eq(0)
    end

    it 'returns only users interested in a specific vkeys' do
      users = fetch_all(:users, User, @admin, @vehicle_users.length, vkeys: @vehicle.vkeys)
      expect(users).to match_array(@vehicle_users)
    end

    it 'returns no users for an uninteresting vkeys' do
      users = fetch_all(:users, User, @admin, 0, vkeys: @uninteresting_vehicle.vkeys)
      expect(users.length).to eq(0)
    end

    it 'returns only users with an active recall subscription' do
      users = fetch_all(:users, User, @admin, @recall_users.length, subscription: 'recalls')
      expect(users).to match_array(@recall_users)
    end

    it 'returns only users with an active vehicle subscription' do
      users = fetch_all(:users, User, @admin, @vehicle_users.length, subscription: 'vehicles')
      expect(users).to match_array(@vehicle_users)
    end

    it 'returns all users for an unknown subscription type' do
      users = fetch_all(:users, User, @admin, 0, subscription: 'notasubscription')
      expect(users.length).to eq(@users.length)
    end

    it 'returns all users wanting a recall summary' do
      total = Constants::MAXIMUM_PAGE_SIZE
      users = fetch_all(:users, User, @admin, total, summary: 'recalls')
      expect(users).to match_array(@recall_users.slice(Constants::MAXIMUM_PAGE_SIZE, total))
    end

    it 'returns all users wanting a recall summary' do
      total = Constants::MAXIMUM_PAGE_SIZE / 2
      users = fetch_all(:users, User, @admin, total, summary: 'vehicles')
      expect(users).to match_array(@vehicle_users.slice(Constants::MAXIMUM_PAGE_SIZE / 2, total))
    end

  end

  describe 'Updating User Status' do

    before :example do
      @admin = create(:admin)
      @admin.refresh_access_token!

      @users = []
      5.times do
        @users << create(:user)
      end

      @error_users = []
      6.times do
        @error_users << create(:user)
      end
    end

    after :example do
      User.destroy_all
    end

    it 'increments the email error counts' do
      params = {
        emailError: true,
        users: @error_users.map{|u| u.id.to_s}.join(',')
      }
      put '/users/status', params: params, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      @error_users.each do |u|
        u.reload
        expect(u.email_errors).to eq(1)
      end
    end

    it 'only increments the email error counts of passed users' do
      params = {
        emailError: true,
        users: @error_users.map{|u| u.id.to_s}.join(',')
      }
      put '/users/status', params: params, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      @users.each do |u|
        u.reload
        expect(u.email_errors).to eq(0)
      end
    end

    it 'clears the email error counts' do
      @error_users.each do |u|
        u.email_errored!
        expect(u.email_errors).to eq(1)
      end

      params = {
        emailSuccess: true,
        users: @error_users.map{|u| u.id.to_s}.join(',')
      }
      put '/users/status', params: params, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      @error_users.each do |u|
        u.reload
        expect(u.email_errors).to eq(0)
      end
    end

    it 'only clears the email error counts of passed users' do
      @error_users.each do |u|
        u.email_errored!
        expect(u.email_errors).to eq(1)
      end
      @users.each do |u|
        u.email_errored!
        expect(u.email_errors).to eq(1)
      end

      params = {
        emailSuccess: true,
        users: @error_users.map{|u| u.id.to_s}.join(',')
      }
      put '/users/status', params: params, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      @users.each do |u|
        u.reload
        expect(u.email_errors).to eq(1)
      end
    end

    it 'raises a BadRequestError if no users are supplied' do
      put '/users/status', params: {}, headers: auth_headers(@admin)
      expect(response).to have_http_status(:bad_request)
    end

  end

  describe 'Create a User' do

    before :example do
      @user = create(:user)
      @user.refresh_access_token!

      @new_user = build(:user,
        id: nil,
        email_confirmed_at: nil,
        phone: '123.456.7890',
        phone_confirmed_at: nil,
        count_subscriptions: 0)
      @json = @new_user.as_json
      @json[:data][:attributes].merge!({ password: 'pa$$W0rdpa$$W0rd' })

      clear_enqueued_jobs
      clear_performed_jobs
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      User.destroy_all
    end

    it 'requires a ReCAPTCHA token' do
      post '/users', params: { user: @json }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success without a user' do
      post '/users', params: { user: @json, recaptcha: 'ignored' }
      expect(response).to have_http_status(:success)
    end

    it 'returns http success with a user' do
      post '/users', params: { user: @json, recaptcha: 'ignored' }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the document' do
      post '/users', params: { user: @json, recaptcha: 'ignored' }

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid

      expect(purge_id(u.as_json(flat: true))).to eq(@new_user.as_json(flat: true))
    end

    it 'return creates the document' do
      post '/users', params: { user: @json, recaptcha: 'ignored' }

      expect(response.body).to be_present

      u = User.find(User.from_json(response.body).id) rescue nil
      expect(u).to be_present
    end

    it 'ignores the passed id' do
      invalid_id = '1' * 24
      @json[:data][:id] = invalid_id.as_json
      post '/users', params: { user: @json, recaptcha: 'ignored' }

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.id.to_s).to_not eq(invalid_id)

      u = User.find(u.id) rescue nil
      expect(u).to be_present

      u = begin
            User.find(invalid_id)
          rescue Mongoid::Errors::DocumentNotFound
            nil
          end
      expect(u).to be_nil
    end

    it 'returns errors for invalid documents' do
      @json[:data][:attributes][:email] = nil
      post '/users', params: { user: @json, recaptcha: 'ignored' }

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Email ')
    end

    it 'returns errors for nested documents' do
      @new_user.preference.categories = ['illegal']
      json = @new_user.as_json
      json[:data][:attributes].merge!({ password: 'pa$$W0rdpa$$W0rd' })
      post '/users', params: { user: json, recaptcha: 'ignored' }

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Preference categories ')
    end

    it 'handles no values at all' do
      post '/users', params: { recaptcha: 'ignored' }

      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'sends mail to adminstrators' do
      assert_no_enqueued_jobs

      post '/users', params: { user: @json, recaptcha: 'ignored' }
      expect(response).to have_http_status(:success)
      assert_enqueued_jobs(1, queue: :admin, only: SendNewUsersJob)
    end

  end

  describe 'Retrieve a single User' do

    before :example do
      @admin = create(:admin)
      @admin.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!

      p = build(:preference,
        audience: FeedConstants::DEFAULT_AUDIENCE,
        categories: ['food'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: ['probable', 'possible'],
        alert_by_email: true)
      @user = create(:user, preference: p, count_subscriptions: 2)
      @user.refresh_access_token!

      @ec = create(:email_coupon, email: @user.email)

      @other_user = create(:user)
    end

    after :example do
      EmailCoupon.destroy_all
      User.destroy_all
    end

    it 'returns http forbidden when the user requests another user' do
      get "/users/#{@other_user.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success when the user requests their own record' do
      get "/users/#{@user.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success when the user with a cancelled plan requests their own record' do
      user = create(:user)
      user.refresh_access_token!
      expire_all!(user)
      
      get "/users/#{user.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:success)
    end

    it 'returns https success for administrators' do
      get "/users/#{@other_user.id}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns https success for workers' do
      get "/users/#{@other_user.id}", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns the requested document' do
      get "/users/#{@other_user.id}", headers: auth_headers(@admin)

      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(User.from_json(json).as_json(flat: true)).to eq(@other_user.as_json(flat: true))
    end

    it 'does not return the access token' do
      get "/users/#{@other_user.id}", headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access
      expect(json).to be_a(Hash)
      expect(json).to have_key(:data)
      expect(json[:data]).to have_key(:attributes)
      expect(json[:data][:attributes]).to_not have_key(:access_token)
    end

    it 'returns the Preference as a subdocument' do
      get "/users/#{@other_user.id}", headers: auth_headers(@admin)

      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)

      json = json.with_indifferent_access
      expect(json[:data][:attributes]).to have_key(:preference)
      expect(json[:data][:attributes][:preference]).to be_a(Hash)
    end

    it 'returns the users plans as related content' do
      expect(@user.active_plans.length).to be >= 1

      get "/users/#{@user.id}", headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access

      related = json[:included]
      expect(related).to be_a(Array)

      related = JsonEnvelope.from_related(related, all_fields: true).filter{|r| r.is_a?(Plan)}
      expect(related.length).to eq(@user.active_plans.length)

      expect(related.sort).to match_array(@user.active_plans)
    end

    it 'returns the users coupon as related content' do
      get "/users/#{@user.id}", headers: auth_headers(@admin)

      json = JSON.parse(response.body).with_indifferent_access

      related = json[:included]
      expect(related).to be_a(Array)

      related = JsonEnvelope.from_related(related, all_fields: true).filter{|r| r.is_a?(Coupon)}
      expect(related.length).to eq(1)

      expect(related).to match_array([@ec.coupon])
    end

    it 'returns an error for unknown documents' do
      get "/users/#{'1' * 24}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

  end

  describe 'Update a User' do

    before :example do
      @admin = create(:admin)
      @admin.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!

      p = build(:preference,
        audience: FeedConstants::DEFAULT_AUDIENCE,
        categories: ['food'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: ['probable', 'possible'],
        alert_by_email: true)
      @user = create(:user, preference: p)
      @user.refresh_access_token!

      @other_user = create(:user, password: 'pa$$W0rdpa$$W0rd')
      @other_user.refresh_access_token!

      @first_name = @other_user.first_name
      @last_name = @other_user.last_name
      @other_user.last_name = 'Tester'
      @json = @other_user.as_json
    end

    after :example do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for a user updating their record' do
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@other_user)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success when the user with a cancelled plan requests their own record' do
      expire_all!(@other_user)
      
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@other_user)
      expect(response).to have_http_status(:success)
    end

    it 'returns http forbidden for a user updating another record' do
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for administrators' do
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns the document' do
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.id).to eq(@other_user.id)

      expect(u.as_json[:data]).to eq(@json[:data])
    end

    it 'only updates the change fields' do
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.first_name).to eq(@first_name)
      expect(u.last_name).to_not eq(@last_name)
    end

    it 'disallows changes to the user role for normal users' do
      @other_user.role = 'worker'
      put "/users/#{@other_user.id}", params: { user: @other_user.as_json }, as: :json, headers: auth_headers(@other_user)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.role).to eq('member')
    end

    it 'allows changes to the user role for admins' do
      @other_user.role = 'worker'
      put "/users/#{@other_user.id}", params: { user: @other_user.as_json }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.role).to eq('worker')
    end

    it 'allows changes to the user role for workers' do
      @other_user.role = 'worker'
      put "/users/#{@other_user.id}", params: { user: @other_user.as_json }, as: :json, headers: auth_headers(@worker)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.role).to eq('worker')
    end

    it 'updates the Preference only if the User did not change' do
      @other_user.last_name = @last_name
      @other_user.preference.categories = ['animals', 'food']
      put "/users/#{@other_user.id}", params: { user: @other_user.as_json }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid

      expect(u.as_json).to eq(@other_user.as_json)
      expect(u.preference.categories).to match_array(['animals', 'food'])
    end

    it 'ignores the id within the document' do
      invalid_id = '1' * 24
      @json[:data][:id] = invalid_id.to_s
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.id).to eq(@other_user.id)

      @json[:data][:id] = @other_user.id.to_s
      expect(u.as_json[:data]).to eq(@json[:data])
    end

    it 'returns errors for invalid documents' do
      @json[:data][:attributes][:email] = nil
      put "/users/#{@other_user.id}", params: { user: @json }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Email ')
    end

    it 'returns an error for unknown documents' do
      put "/users/#{'1' * 24}", params: { user: @json }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'returns errors for nested documents' do
      @user.preference.audience = 'notanaudience'
      put "/users/#{@user.id}", params: { user: @user.as_json }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Preference audience ')
    end

    it 'makes no changes when passed no values' do
      put "/users/#{@other_user.id}", as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      u = User.from_json(response.body)
      expect(u).to be_valid
      expect(u.id).to eq(@other_user.id)

      @json[:data][:attributes][:lastName] = @last_name
      expect(u.as_json[:data]).to eq(@json[:data])
    end

  end

  describe 'Delete a User' do

    before :example do
      @admin = create(:admin)
      @admin.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!

      p = build(:preference,
        audience: FeedConstants::DEFAULT_AUDIENCE,
        categories: ['food'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: ['probable', 'possible'],
        alert_by_email: true)
      @user = create(:user, preference: p)
      @user.refresh_access_token!

      @other_user = create(:user)
      @id = @other_user.id
      @password_digest = User.find(@id).password_digest

      @destroyed = load_stripe('customer_deleted.json')
    end

    after :example do
      User.destroy_all
    end

    it 'returns http forbidden for non-admin users' do
      delete "/users/#{@other_user.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for admins' do
      expect(Stripe::Customer).to receive(:delete).and_return(@destroyed)

      delete "/users/#{@other_user.id}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:ok)
    end

    it 'returns http forbidden if an admin deletes themselves' do
      delete "/users/#{@admin.id}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for worker' do
      expect(Stripe::Customer).to receive(:delete).and_return(@destroyed)

      delete "/users/#{@other_user.id}", headers: auth_headers(@worker)
      expect(response).to have_http_status(:ok)
    end

    it 'returns http forbidden if a worker deletes themselves' do
      delete "/users/#{@worker.id}", headers: auth_headers(@worker)
      expect(response).to have_http_status(:forbidden)
    end

    it 'return only the head' do
      expect(Stripe::Customer).to receive(:delete).and_return(@destroyed)

      delete "/users/#{@other_user.id}", headers: auth_headers(@admin)
      expect(response.body).to be_blank
    end

    it 'returns an error for unknown documents' do
      delete "/users/#{'1' * 24}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

  end

end
