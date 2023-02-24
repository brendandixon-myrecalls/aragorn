require 'rails_helper'
require 'aws_helper'
include ActiveJob::TestHelper

describe 'Vin', type: :request do

  before :all do
    # Reserve the first VIN for update tests
    vins = TestConstants::VINS.slice(1, TestConstants::VINS.length-1)
    @recalls = vins.map{|vin| create(:vehicle_recall, vehicles: [build(:vehicle, vin: vin)])}
    (vins.length / 2).times do |i|
      @recalls << create(:vehicle_recall, vehicles: [build(:vehicle, vin: select_from(vins).first)])
    end
  end

  after :all do
    VehicleRecall.destroy_all
  end

  describe 'Retrieving VINs' do

    before :all do
      @user = create(:user, count_subscriptions: 5)
      @inactive_subscription = @user.subscriptions.last
      expire_at(@inactive_subscription, 1.month.ago)
      @user.save!
      @user.reload
      @user.refresh_access_token!

      @worker = create(:worker)
      @worker.refresh_access_token!
    end

    after :all do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      get "/users/#{@user.id}/vins"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      get "/users/#{@user.id}/vins", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the active vins for the user' do
      get "/users/#{@user.id}/vins", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      count = @user.subscriptions.sum{|s| s.active? ? s.vins.length : 0}
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      vins = @user.subscriptions.select{|s| s.active?}.map{|s| s.vins}.flatten.sort
      data.each_with_index do |d, i|
        expect(d).to eq(vins[i].as_json(exclude_self_link: true)[:data])
      end
    end

    it 'returns all the vins for the user' do
      get "/users/#{@user.id}/vins", params: {all: true}, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      count = @user.subscriptions.sum{|s| s.vins.length}
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      vins = @user.subscriptions.map{|s| s.vins}.flatten.sort
      data.each_with_index do |d, i|
        expect(d).to eq(vins[i].as_json(exclude_self_link: true)[:data])
      end
    end

    it 'includes the related recalls when requested' do
      get "/users/#{@user.id}/vins", params: {recalls: true}, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      count = @user.subscriptions.sum{|s| s.active? ? s.vins.length : 0}
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      vins = @user.subscriptions.select{|s| s.active?}.map{|s| s.vins}.flatten.sort
      data.each_with_index do |d, i|
        expect(d).to eq(vins[i].as_json(exclude_self_link: true)[:data])
      end

      recalls = @user.vins.map{|v| v.recalls}.flatten.uniq
      related = json[:included]
      expect(related).to be_a(Array)
      expect(related.length).to eq(recalls.length)
      recalls.each do |r|
        expect(related).to include(r.as_json[:data].deep_symbolize_keys)
      end
    end

    it 'allows workers to retrieve vins for another user' do
      get "/users/#{@user.id}/vins", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      count = @user.subscriptions.sum{|s| s.active? ? s.vins.length : 0}
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      vins = @user.subscriptions.select{|s| s.active?}.map{|s| s.vins}.flatten.sort
      data.each_with_index do |d, i|
        expect(d).to eq(vins[i].as_json(exclude_self_link: true)[:data])
      end
    end

    it 'allows workers to retrieve vins for another user' do
      get "/users/#{@worker.id}/vins", params: {email: @user.email}, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      count = @user.subscriptions.sum{|s| s.active? ? s.vins.length : 0}
      json = JSON.parse(response.body).deep_symbolize_keys
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(count)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      vins = @user.subscriptions.select{|s| s.active?}.map{|s| s.vins}.flatten.sort
      data.each_with_index do |d, i|
        expect(d).to eq(vins[i].as_json(exclude_self_link: true)[:data])
      end
    end

  end

  describe 'Retrieving a single VIN' do

    before :all do
      @user = create(:user, count_vins: 0)
      s = @user.subscriptions.first
      expect(s.count_vins).to be > 0
      s.vins = (0...s.count_vins).to_a.map do
        vr = select_from(@recalls).first
        build(:vin, reviewed: true, vin: vkey_to_vin(select_from(vr.vehicles).first.to_vkey))
      end
      @user.save!
      @user.refresh_access_token!

      @vin = @user.vins.first

      @worker = create(:worker)
      @worker.refresh_access_token!
    end

    after :all do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      get "/users/#{@user.id}/vins/#{@vin.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      get "/users/#{@user.id}/vins/#{@vin.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the vin' do
      get "/users/#{@user.id}/vins/#{@vin.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@vin.as_json)
    end

    it 'includes the related recalls when requested' do
      get "/users/#{@user.id}/vins/#{@vin.id}", params: {recalls: true}, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      related = json.delete(:included)
      expect(json).to eq(@vin.as_json)

      recalls = @vin.recalls
      expect(related).to be_a(Array)
      expect(related.length).to eq(recalls.length)
      recalls.each do |r|
        expect(related).to include(r.as_json[:data].deep_symbolize_keys)
      end
    end

    it 'allows workers to retrieve the vins for another user' do
      get "/users/#{@user.id}/vins/#{@vin.id}", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@vin.as_json)
    end

    it 'allows workers to retrieve the vins for another user by email' do
      get "/users/#{@worker.id}/vins/#{@vin.id}", params: {email: @user.email}, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@vin.as_json)
    end

  end

  describe 'Updating a VIN' do

    before :each do
      # Reserve and use the first VIN for update tests

      @user = create(:user, count_vins: 0)
      s = @user.subscriptions.first
      expect(s.count_vins).to be > 0
      s.vins = (1...s.count_vins).inject([build(:vin, vin: nil)]) do |vins, i|
        vins << build(:vin, vin: TestConstants::VINS[i])
      end
      expect(s.vins.first).to_not be_reviewed
      s.vins.slice(1, s.count_vins).each do |v|
        expect(v).to be_reviewed
      end
      @user.save!

      @other = create(:user, count_vins: 0)
      so = @other.subscriptions.first
      expect(so.count_vins).to eq(s.count_vins)
      so.vins = (0...so.count_vins).inject([]) do |vins, i|
        vins << build(:vin, vin: TestConstants::VINS[i+1])
      end
      so.vins.each do |v|
        expect(v).to be_reviewed
      end
      @other.save!

      @empty_vin = @user.vins.first
      @vin = @user.vins.second

      @worker = create(:worker)

      travel_to 1.year.from_now

      @user.refresh_access_token!
      @worker.refresh_access_token!

      clear_enqueued_jobs
      clear_performed_jobs
    end

    after :each do
      clear_enqueued_jobs
      clear_performed_jobs

      travel_back

      User.destroy_all
    end

    it 'requires a signed-in user' do
      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns http conflict if updating the VIN number and the VIN disallows updates' do
      travel_to 1.year.ago

      @vin.vin = TestConstants::VINS.first

      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:conflict)
    end

    it 'returns http success updating campaigns even if the VIN disallows updates' do
      travel_to 1.year.ago

      @vin.campaigns = select_from(TestConstants::CAMPAIGNS, 3)

      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the updated vin' do
      new_vin = TestConstants::VINS.first
      @vin.vin = new_vin

      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      @user.reload
      @vin = @user.vin_from_id(@vin.id)
      expect(@vin.vin).to eq(new_vin)

      json = JSON.parse(response.body).deep_symbolize_keys
      expect(json).to eq(@vin.as_json)
    end

    it 'updates the subscription' do
      @vin.vehicle.make = 'Yugo'

      s = @vin.subscription
      expect(s.vkeys).to_not include(@vin.to_vkey)

      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      @user.reload
      @vin = @user.vin_from_id(@vin.id)
      expect(@vin.vehicle.make).to eq('Yugo')

      s = @vin.subscription
      expect(s.vkeys).to include(@vin.to_vkey)
    end

    it 'marks the VIN unreviewed if no other user has an interest in the vkey' do
      @empty_vin.vin = TestConstants::VINS.first
      @empty_vin.vehicle = build(:vehicle, vin: @empty_vin.vin)

      put "/users/#{@user.id}/vins/#{@empty_vin.id}", params: { vin: @empty_vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      @user.reload
      @empty_vin = @user.vin_from_id(@empty_vin.id)
      expect(@empty_vin).to_not be_reviewed
    end

    it 'marks the VIN reviewed if another user has an interest in the vkey' do
      @empty_vin.vin = @other.subscriptions.first.vins.first.vin
      @empty_vin.vehicle = build(:vehicle, vin: @empty_vin.vin)

      put "/users/#{@user.id}/vins/#{@empty_vin.id}", params: { vin: @empty_vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      @user.reload
      @empty_vin = @user.vin_from_id(@empty_vin.id)
      expect(@empty_vin).to be_reviewed
    end

    it 'initiates reviewing VINs if a VIN needs review' do
      assert_no_enqueued_jobs

      @empty_vin.vin = TestConstants::VINS.first
      @empty_vin.vehicle = build(:vehicle, vin: @empty_vin.vin)

      put "/users/#{@user.id}/vins/#{@empty_vin.id}", params: { vin: @empty_vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      @user.reload
      @empty_vin = @user.vin_from_id(@empty_vin.id)
      expect(@empty_vin).to_not be_reviewed

      assert_enqueued_with(job: SendAlertsJob, args: ["review_vins"], queue: "alerts")
    end

    it 'requests the alerter to review vins and send vehicle recall alerts' do
      invoked = false
      allow(AwsHelper).to receive(:invoke) {|name, **args|
        expect(name).to eq(SendAlertsJob::ALERTER_FUNCTION)
        expect(**args).to eq(reviewVins: true, sendVehicleRecallAlerts: true)
        invoked = true
        true
      }

      assert_no_enqueued_jobs

      @empty_vin.vin = TestConstants::VINS.first
      @empty_vin.vehicle = build(:vehicle, vin: @empty_vin.vin)

      perform_enqueued_jobs do
        put "/users/#{@user.id}/vins/#{@empty_vin.id}", params: { vin: @empty_vin.as_json }, headers: auth_headers(@user)
        expect(response).to have_http_status(:success)

        @user.reload
        @empty_vin = @user.vin_from_id(@empty_vin.id)
        expect(@empty_vin).to_not be_reviewed
      end

      expect(invoked).to be true
      assert_performed_jobs(1, queue: :alerts)
    end

    it 'does not initiate reviewing VINs if no VIN needs review' do
      assert_no_enqueued_jobs

      @empty_vin.vin = @other.subscriptions.first.vins.first.vin
      @empty_vin.vehicle = build(:vehicle, vin: @empty_vin.vin)

      put "/users/#{@user.id}/vins/#{@empty_vin.id}", params: { vin: @empty_vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      @user.reload
      @empty_vin = @user.vin_from_id(@empty_vin.id)
      expect(@empty_vin).to be_reviewed

      assert_no_enqueued_jobs only: SendAlertsJob
    end

    it 'includes the related recalls when requested' do
      put "/users/#{@user.id}/vins/#{@vin.id}", params: { recalls: true, vin: @vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).deep_symbolize_keys
      related = json.delete(:included)

      @user.reload
      @vin = @user.vin_from_id(@vin.id)
      expect(json).to eq(@vin.as_json)

      recalls = @vin.recalls
      expect(related).to be_a(Array)
      expect(related.length).to eq(recalls.length)
      recalls.each do |r|
        expect(related).to include(r.as_json[:data].deep_symbolize_keys)
      end
    end

    it 'returns errors for invalid documents' do
      @vin.vin = 'notavin'
      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }, headers: auth_headers(@user)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('notavin is ')
    end

    it 'returns errors for nested documents' do
      @vin.vehicle.year = Time.now + Vehicle::MAXIMUM_YEARS_HENCE + 1
      put "/users/#{@user.id}/vins/#{@vin.id}", params: { vin: @vin.as_json }, headers: auth_headers(@user)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Vehicle year ')
    end

  end

  describe 'Marking a VIN reviewed' do

    before :each do
      @user = create(:user)
      @worker = create(:worker)

      @vin = @user.vins.first
      @vin.reviewed = false
      @user.save!

      @user.refresh_access_token!
      @worker.refresh_access_token!
    end

    after :each do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      @vin.reviewed = true

      put "/vins/#{@vin.id}/reviewed", params: { vin: @vin.as_json }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows workers to mark a VIN reviewed' do
      @vin.reviewed = true

      put "/vins/#{@vin.id}/reviewed", params: { vin: @vin.as_json }, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)

      @user.reload
      @vin = @user.vins.first
      expect(@vin).to be_reviewed
    end

    it 'disallows normal users to mark a VIN reviewed' do
      @vin.reviewed = true

      put "/vins/#{@vin.id}/reviewed", params: { vin: @vin.as_json }, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)

      @user.reload
      @vin = @user.vins.first
      expect(@vin).to_not be_reviewed
    end

  end

  describe 'Finding unreviewed VINs' do

    before :each do
      @user = create(:user)
      expect(@user.unreviewed_vins.length).to eq(0)

      5.times do
        u = create(:user)
        expect(u.unreviewed_vins.length).to eq(0)
      end

      @count_vins = 0
      4.times do
        u = create(:user)
        expect(u.unreviewed_vins.length).to eq(0)
        u.subscriptions.each do |s|
          s.vins.each do |v|
            @count_vins += 1
            v.reviewed = false
          end
        end
        u.save!
      end

      @worker = create(:worker)

      @user.refresh_access_token!
      @worker.refresh_access_token!
    end

    after :each do
      User.destroy_all
    end

    it 'requires a signed-in user' do
      get '/vins/unreviewed'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      get '/vins/unreviewed', headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for workers' do
      get '/vins/unreviewed', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns an array of documents' do
      get '/vins/unreviewed', headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(@count_vins)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(@count_vins)

      data = Vin.from_json({ vins: json })
      data.each do |v|
        expect(v).to_not be_reviewed
      end
    end

  end

end
