require 'rails_helper'
require 'aws_helper'
include ActiveJob::TestHelper

describe 'VehicleRecalls Management', type: :request do

  def data_only(h)
    data = (h[:data] || {}).reject{|k, v| ['id', :id, :_id].include?(k) }
    if (data[:attributes] || {})[:vehicles].present?
      data[:attributes][:vehicles] = data[:attributes][:vehicles].map do |vh|
        vh.reject{|k, v| ['id', :id, :_id].include?(k) }
      end
    end
    data
  end

  before :all do
    @admin = create(:admin)
    @admin.refresh_access_token!

    @user = create(:user, count_vins: 0)
    @user.subscriptions.each do |s|
      s.vins = (0...s.plan.vins).map{ build(:vin) }
    end
    @user.save!
    @user.refresh_access_token!

    @worker = create(:worker)
    @worker.refresh_access_token!

    clear_enqueued_jobs
    clear_performed_jobs
  end

  after :all do
    User.destroy_all
  end

  describe 'Retrieving / searching Recalls' do

    before :all do
      # Note:
      # - Ensure the array is stably sorted by publication date
      #   The controller only sorts on publication date
      #   VehicleRecalls first on publication date and then campaign identifier
      # - BSON::DateTime stores only milliseconds

      @dates = []
      @loaded = []

      date = 1.day.ago
      15.times do |i|
        date = date.beginning_of_minute
        @dates << date
        @loaded << create(:vehicle_recall,
          publication_date: date,
          state: 'sent')
        date -= 1.day
      end

      10.times do |i|
        date = date.beginning_of_minute
        @dates << date
        @loaded << create(:vehicle_recall,
          publication_date: date,
          state: 'reviewed')
        date -= 1.day
      end

      # These recalls are too old to appear in any legitimate search
      @ignored = []
      5.times do |i|
        date = Constants::MINIMUM_VEHICLE_DATE - 1.second
        @ignored << create(:vehicle_recall,
          publication_date: date,
          state: 'sent')
      end

      expect(VehicleRecall.count).to eq(@loaded.length + @ignored.length)
      expect(VehicleRecall.needs_sending.count).to eq(10)
      expect(VehicleRecall.was_sent.count).to eq(20)
    end

    after :all do
      clear_enqueued_jobs
      clear_performed_jobs
      VehicleRecall.destroy_all
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    it 'requires a signed-in user' do
      get '/vehicle_recalls'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      get '/vehicle_recalls', headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for workers' do
      get '/vehicle_recalls', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for admins' do
      get '/vehicle_recalls', headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns an array of documents' do
      count = [@loaded.length, Constants::MAXIMUM_PAGE_SIZE].min
      get '/vehicle_recalls', params: { limit: count }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(@loaded.length)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = VehicleRecall.from_json({ vehicleRecalls: json })
      expect(data).to match_array(@loaded.slice(0, count))
    end

    it 'returns the documents sorted by descending publication date' do
      count = [@loaded.length, Constants::MAXIMUM_PAGE_SIZE].min
      get '/vehicle_recalls', params: { limit: count }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = VehicleRecall.from_json({ vehicleRecalls: json })
      prev_date = DateTime.tomorrow
      data.each do |r|
        expect(r.publication_date).to be <= prev_date
        prev_date = r.publication_date
      end
    end

    it 'returns a limited-size array of documents' do
      count = 5
      get '/vehicle_recalls', params: { limit: count }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = VehicleRecall.from_json({ vehicleRecalls: json })
      expect(data.sort).to match_array(@loaded.slice(0, count))
    end

    it 'limits the documents returned to those available' do
      total = @loaded.length
      count = [total, Constants::MAXIMUM_PAGE_SIZE].min
      offset = total - (Constants::MAXIMUM_PAGE_SIZE / 2)
      get '/vehicle_recalls', params: { limit: count, offset: offset  }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(total - offset)

      data = VehicleRecall.from_json({ vehicleRecalls: json })
      expect(data).to match_array((@loaded).slice(offset, count))
    end

    it 'returns documents starting at the requested offset' do
      count = 5
      get '/vehicle_recalls', params: { limit: count, offset: count }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = VehicleRecall.from_json({ vehicleRecalls: json })
      expect(data).to match_array(@loaded.slice(count, count))
    end

    it 'returns no documents if presented with an excessive offset' do
      count = 5
      get '/vehicle_recalls', params: { limit: count, offset: @loaded.length * 42 }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(0)
    end

    it 'limits negative offsets to available documents' do
      count = 5
      get '/vehicle_recalls', params: { limit: count, offset: -42 }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = VehicleRecall.from_json({ vehicleRecalls: json })
      expect(data).to match_array(@loaded.slice(0, count))
    end

    it 'ignores a passed document total' do
      count = 5
      get '/vehicle_recalls', params: { limit: count, offset: @loaded.length * 42, total: @loaded.length * 10000 }, headers: auth_headers(@worker)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(0)
    end

    it 'returns only recalls with the specified IDs' do
      ids = VehicleRecall.limit(7).map{|r| r.id.to_s}
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, 7, recalls: ids.join(','))
      expect(recalls.length).to eq(7)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'rejects invalid recall IDs' do
      ids = VehicleRecall.limit(5).map{|r| r.id.to_s}.each_with_index{|id, i| i % 2 ? id : nil}.compact
      expected_count = ids.length
      ids += ['not-really-a-legal-id', 'this-is-not-an-id-either']

      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, expected_count, recalls: ids.join(','))
      expect(recalls.length).to eq(expected_count)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'ignores unknown recall IDs' do
      ids = Recall.limit(9).map{|r| r.id.to_s}.each_with_index{|id, i| i % 2 ? id : nil}.compact
      expected_count = ids.length
      ids += [BSON::ObjectId.new.to_s, BSON::ObjectId.new.to_s]

      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, expected_count, recalls: ids.join(','))
      expect(recalls.length).to eq(expected_count)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'only returns recalls published on or after the minimum date' do
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, @loaded.length)
      expect(recalls.length).to eq(@loaded.length)
      recalls.each do |r|
        expect(r.publication_date).to be >= Constants::MINIMUM_VEHICLE_DATE
      end
    end

    it 'limits recalls to those published on or after the minimum date' do
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, @loaded.length, after: Constants::MINIMUM_VEHICLE_DATE - 1.second)
      expect(recalls.length).to eq(@loaded.length)
      recalls.each do |r|
        expect(r.publication_date).to be >= Constants::MINIMUM_VEHICLE_DATE
      end
    end

    it 'returns only recalls published on or after a given date' do
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, 6, after: @dates[5])
      expect(recalls.length).to eq(6)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[5]
      end
    end

    it 'returns only recalls published on or before a given date' do
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, 14, before: @dates[11])
      expect(recalls.length).to eq(14)
      recalls.each do |r|
        expect(r.publication_date).to be <= @dates[11]
      end
    end

    it 'returns recalls for the requested campaigns' do
      campaigns = select_from(@loaded, 7, ensure_unique: true)
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, campaigns.length, campaigns: campaigns.map{|vr| vr.campaign_id})
      expect(recalls.length).to eq(campaigns.length)
      recalls.each do |r|
        expect(campaigns).to include(r)
      end
    end

    it 'returns recalls for the requested vkeys' do
      values = select_from(@loaded, 11)
      vkeys = values.map{|vr| vr.vkeys}.flatten.uniq
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, -1, vkeys: vkeys)
      expect(recalls.length).to be >= 11
      values.each do |v|
        expect(recalls).to include(v)
      end
      recalls.each do |r|
        expect(vkeys & r.vkeys).to be_present
      end
    end

    it 'returns reviewed recalls' do
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, 10, state: 'reviewed')
      expect(recalls.length).to eq(10)
      recalls.each do |r|
        expect(r).to be_reviewed
      end
    end

    it 'returns sent recalls' do
      recalls = fetch_all(:vehicle_recalls, VehicleRecall, @worker, 15, state: 'sent')
      expect(recalls.length).to eq(15)
      recalls.each do |r|
        expect(r).to be_sent
      end
    end

    it 'does not return a summary to users' do
      get '/vehicle_recalls/summary', headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns a summary of recent recalls to workers' do
      dates = @dates.slice(3...-4)
      after = dates.last.beginning_of_day.utc
      before = dates.first.end_of_day.utc

      recalls = VehicleRecall.in_published_order.published_during(after, before)

      total = recalls.count
      vkeys = recalls.map{|r| r.vkeys}.flatten.uniq
      impactedUsers = User.has_interest_in_vkey(vkeys).map{|u| u.id.to_s}

      get '/vehicle_recalls/summary', params: { after: after, before: before }, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
      expect(response.body).to be_present

      summary = JSON.parse(response.body).deep_symbolize_keys[:data]
      expect(summary[:total]).to eq(total)
      expect(summary[:totalAffectedVehicles]).to eq(vkeys.length)
      expect(summary[:impactedUsers]).to match_array(impactedUsers)
    end

    it' returns a summary to admins' do
      get '/vehicle_recalls/summary', headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
      expect(response.body).to be_present
    end

  end

  describe 'Create a Recall' do

    before :example do
      @recall = build(:vehicle_recall)
      @r = @recall.as_json(exclude_self_link: true)
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      VehicleRecall.destroy_all
    end

    it 'requires a signed-in user' do
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns the document' do
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = VehicleRecall.from_json(response.body)
      expect(r).to be_valid

      expect(data_only(r.as_json(exclude_self_link: true))).to eq(data_only(@r))
    end

    it 'creates the document' do
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)

      r = VehicleRecall.from_json(response.body)
      vr = VehicleRecall.find(r.id) rescue nil
      expect(vr).to be_present
    end

    it 'uploads the document to S3' do
      recall_uploaded = false

      aws_helper = class_spy('AwsHelper')
      allow(AwsHelper).to receive(:upload_recall).with(having_attributes(data_only(@recall))) { recall_uploaded = true }

      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)
      expect(recall_uploaded).to be true
    end

    it 'returns see-other if the document exists' do
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:see_other)
    end

    it 'ignores the passed id' do
      invalid_id = BSON::ObjectId.new
      @r[:data][:id] = invalid_id.as_json
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = VehicleRecall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to_not eq(invalid_id)

      vr = VehicleRecall.find(r.id) rescue nil
      expect(vr).to be_present

      r = begin
            VehicleRecall.find(invalid_id)
          rescue Mongoid::Errors::DocumentNotFound
            nil
          end
      expect(r).to be_nil
    end

    it 'returns errors for invalid documents' do
      @r[:data][:attributes][:state] = 'notastate'
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('State ')
    end

    it 'returns nested errors for invalid documents' do
      @r[:data][:attributes][:vehicles].first[:year] = Time.now.year + Vehicle::MAXIMUM_YEARS_HENCE + 1
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Vehicle year ')
    end

    it 'handles no values at all' do
      post '/vehicle_recalls', headers: auth_headers(@admin)

      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'sends alerts for reviewed recalls' do
      assert_no_enqueued_jobs
      @r[:data][:attributes][:state] = 'reviewed'
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_enqueued_jobs(1, queue: :alerts)
      assert_no_enqueued_jobs only: SendReviewNeededJob
    end

    it 'does not send alerts for sent recalls' do
      assert_no_enqueued_jobs
      @r[:data][:attributes][:state] = 'sent'
      post '/vehicle_recalls', params: { vehicleRecall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs only: SendAlertsJob
    end

  end

  describe 'Retrieve a single Recall' do

    before :example do
      @recall = create(:vehicle_recall)
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      VehicleRecall.destroy_all
    end

    it 'requires a signed-in user' do
      get "/vehicle_recalls/#{@recall.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for members' do
      get "/vehicle_recalls/#{@recall.id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for workers' do
      get "/vehicle_recalls/#{@recall.id}", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for admins' do
      get "/vehicle_recalls/#{@recall.id}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns the requested document' do
      get "/vehicle_recalls/#{@recall.id}", headers: auth_headers(@worker)

      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(VehicleRecall.from_json(json)).to eq(@recall)
    end

    it 'returns an error for unknown documents' do
      get "/vehicle_recalls/#{BSON::ObjectId.new}", headers: auth_headers(@worker)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'returns by campaign id' do
      get "/vehicle_recalls/#{@recall.campaign_id}", headers: auth_headers(@worker)

      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(VehicleRecall.from_json(json)).to eq(@recall)
    end

  end

  describe 'Update a Recall' do

    before :example do
      @recall = create(:vehicle_recall, state: 'reviewed')
      @id = @recall.id

      5.times { create(:vehicle_recall, state: 'reviewed') }

      expect(VehicleRecall.needs_sending.count).to eq(6)

      @prior = @recall.as_json
      @after = @recall.as_json
      @after[:data][:attributes][:state] = 'sent'
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs

      VehicleRecall.destroy_all
    end

    it 'requires a signed-in user' do
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @after }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @after }, as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @after }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @after }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns the document' do
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @after }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = VehicleRecall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      expect(r.as_json[:data]).to eq(@after[:data])
    end

    it 'uploads the document to S3' do
      recall_uploaded = false

      aws_helper = class_spy('AwsHelper')
      allow(AwsHelper).to receive(:upload_recall).with(@recall) { recall_uploaded = true }

      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @after }, as: :json, headers: auth_headers(@admin)
      expect(recall_uploaded).to be true
    end

    it 'ignores the id within the document' do
      invalid_id = BSON::ObjectId.new
      @after[:data][:id] = invalid_id
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @after }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = VehicleRecall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      @after[:data][:id] = @id.to_s
      expect(r.as_json[:data]).to eq(@after[:data])
    end

    it 'returns errors for invalid documents' do
      @recall.state = 'notastate'
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('State ')
    end

    it 'returns nested errors for invalid documents' do
      @recall.vehicles.first.year = Time.now.year + Vehicle::MAXIMUM_YEARS_HENCE + 1
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Vehicle year ')
    end

    it 'returns an error for unknown documents' do
      put "/vehicle_recalls/#{BSON::ObjectId.new}", params: { vehicleRecall: @after }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'makes no changes when passed no values' do
      put "/vehicle_recalls/#{@id}", params: { id: @id }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = VehicleRecall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      expect(r.as_json[:data]).to eq(@prior[:data])
    end

    it 'sends alerts for reviewed recalls' do
      assert_no_enqueued_jobs
      @recall.state = 'reviewed'
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_enqueued_jobs(1, queue: :alerts)
    end

    it 'only sends alerts if alerts need sending' do
      assert_no_enqueued_jobs

      VehicleRecall.needs_sending.each{|r| r.sent!}
      @recall.reload
      @recall.summary = 'A new summary'
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs
    end

    it 'requests the alerter to send recall alerts' do
      invoked = false
      allow(AwsHelper).to receive(:invoke) {|name, **args|
        expect(name).to eq(SendAlertsJob::ALERTER_FUNCTION)
        expect(**args).to eq(sendVehicleRecallAlerts: true)
        invoked = true
        true
      }

      VehicleRecall.needs_sending.each{|r| r.sent!}

      assert_no_enqueued_jobs

      perform_enqueued_jobs do
        @recall.state = 'reviewed'
        put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@admin)
        expect(response).to have_http_status(:success)
      end

      expect(invoked).to be true
      assert_performed_jobs(1)
    end

    it 'marking a recall sent returns http forbidden for normal users' do
      put "/vehicle_recalls/#{@id}/sent", headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'marking a recall sent returns http success for administrators' do
      put "/vehicle_recalls/#{@id}/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'marking a recall sent returns http success for workers' do
      put "/vehicle_recalls/#{@id}/sent", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'marks the recall as sent' do
      expect(@recall).to_not be_sent

      put "/vehicle_recalls/#{@id}/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      @recall.reload
      expect(@recall).to be_sent
    end

    it 'disallows workers to alter the state of a sent recall' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.state = 'reviewed'
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@user)

      expect(response).to have_http_status(:forbidden)
    end

    it 'disallows workers to alter the state of a sent recall' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.state = 'reviewed'
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@worker)

      expect(response).to have_http_status(:forbidden)
    end

    it 'allows admins to alter the state of a sent recall' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.state = 'reviewed'
      put "/vehicle_recalls/#{@id}", params: { vehicleRecall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
    end

    it 'uploads the document to S3 after marking sent' do
      recall_uploaded = false

      aws_helper = class_spy('AwsHelper')
      allow(AwsHelper).to receive(:upload_recall).with(@recall) { recall_uploaded = true }

      put "/vehicle_recalls/#{@id}/sent", headers: auth_headers(@admin)
      expect(recall_uploaded).to be true
    end

    it 'marking all recalls sent returns http forbidden for normal users' do
      put "/vehicle_recalls/sent", headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'marking all recalls sent returns http success for administrators' do
      put "/vehicle_recalls/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'marking all recalls sent returns http success for workers' do
      put "/vehicle_recalls/sent", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'marks all recalls as sent' do
      expect(VehicleRecall.needs_sending.count).to eq(6)

      put "/vehicle_recalls/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      expect(VehicleRecall.needs_sending.count).to eq(0)
    end

    it 'uploads all the documents to S3 after marking sent' do
      expected = VehicleRecall.needs_sending.count
      actual = 0

      aws_helper = class_spy('AwsHelper')
      VehicleRecall.needs_sending.each do |r|
        allow(AwsHelper).to receive(:upload_recall).with(r) { actual += 1 }
      end

      put "/vehicle_recalls/sent", headers: auth_headers(@admin)
      expect(actual).to eq(expected)
    end

  end

  describe 'Delete a Recall' do

    before :example do
      @r = create(:vehicle_recall)
    end

    after :example do
      VehicleRecall.destroy_all
    end

    it 'requires a signed-in user' do
      delete "/vehicle_recalls/#{@r.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      delete "/vehicle_recalls/#{@r.id}", as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      delete "/vehicle_recalls/#{@r.id}", as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      delete "/vehicle_recalls/#{@r.id}", as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns http no content (204)' do
      delete "/vehicle_recalls/#{@r.id}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:no_content)
    end

    it 'return only the head' do
      delete "/vehicle_recalls/#{@r.id}", headers: auth_headers(@admin)

      expect(response.body).to be_blank
    end

    it 'returns an error for unknown documents' do
      delete "/vehicle_recalls/#{BSON::ObjectId.new}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

  end

end
