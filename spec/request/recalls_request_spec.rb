require 'rails_helper'
require 'aws_helper'
include ActiveJob::TestHelper

def filter_token(h)
  h[:attributes] = h[:attributes].reject{|k, v| ['token', :token].include?(k) }
  h
end

describe 'Recalls Management', type: :request do

  before :all do
    @admin = create(:admin)
    @admin.refresh_access_token!

    p = build(:preference,
      audience: FeedConstants::DEFAULT_AUDIENCE,
      categories: ['food'],
      distribution: USRegions::REGIONS[:nationwide],
      risk: FeedConstants::DEFAULT_RISK)
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

  describe 'Retrieving / searching Recalls' do

    before :all do
      # Note:
      # - Ensure the array is stably sorted by publication date
      #   The controller only sorts on publication date
      #   Recalls first on publication date and then canonical ID
      # - BSON::DateTime stores only milliseconds

      @dates = []
      @all = []
      @sent = []
      @reviewed = []
      @unreviewed = []
      @nonpublic = []
      @ignored = []

      date = 1.day.ago
      25.times do |i|
        date = date.beginning_of_minute
        @dates << date
        r = create(:recall,
          feed_name: 'fda',
          publication_date: date,
          state: 'sent',
          affected: [],
          allergens: ['dairy', 'nuts'],
          categories: ['food'],
          contaminants: [],
          distribution: USRegions::REGIONS[:west],
          risk: 'probable')
        @all << r
        @sent << r
        date -= 1.day
      end

      20.times do |i|
        date = date.beginning_of_minute
        @dates << date
        r = create(:recall,
          feed_name: 'usda',
          publication_date: date,
          state: 'sent',
          affected: [],
          allergens: [],
          categories: ['food'],
          contaminants: [],
          distribution: USRegions::REGIONS[:southwest],
          risk: 'none')
        @all << r
        @sent << r
        date -= 1.day
      end

      15.times do |i|
        date = date.beginning_of_minute
        @dates << date
        r = create(:recall,
          feed_name: 'fda',
          publication_date: date,
          state: 'reviewed',
          affected: [],
          allergens: [],
          audience: ['consumers', 'professionals'],
          categories: ['food', 'drugs'],
          contaminants: ['listeria', 'salmonella'],
          distribution: USRegions::REGIONS[:northeast],
          risk: 'possible')
        @all << r
        @reviewed << r
        date -= 1.day
      end

      10.times do |i|
        date = date.beginning_of_minute
        @dates << date
        r = create(:recall,
          feed_name: 'cpsc',
          publication_date: date,
          state: 'unreviewed',
          affected: ['children'],
          allergens: [],
          categories: ['toys'],
          contaminants: [],
          distribution: USRegions::REGIONS[:midwest],
          risk: 'none')
        @all << r
        @unreviewed << r
        date -= 1.day
      end

      # These recalls will be returned only to adminstrators and workers
      FeedConstants::NONPUBLIC_NAMES.each do |fn|
        date = date.beginning_of_minute
        @dates << date
        r = create(:recall,
          feed_name: fn,
          publication_date: date,
          state: 'sent',
          affected: [],
          allergens: [],
          contaminants: [],
          distribution: USRegions::REGIONS[:nationwide],
          risk: 'none')
        @all << r
        @nonpublic << r
        date -= 1.day
      end

      # These recalls are too old to appear in any legitimate search
      5.times do |i|
        date = Constants::MINIMUM_RECALL_DATE - 1.second
        r = create(:recall,
          feed_name: 'fda',
          publication_date: date,
          state: 'sent',
          affected: [],
          allergens: ['dairy', 'nuts'],
          categories: ['food'],
          contaminants: [],
          distribution: USRegions::REGIONS[:west],
          risk: 'probable')
        @ignored << r
      end

      expect(Recall.count).to eq(@all.length + @ignored.length)
      expect(Recall.needs_review.count).to eq(@unreviewed.length)
      expect(Recall.needs_sending.count).to eq(@reviewed.length)
      expect(Recall.was_sent.count).to eq(@sent.length + @nonpublic.length + @ignored.length)
    end

    after :all do
      clear_enqueued_jobs
      clear_performed_jobs
      Recall.destroy_all
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
    end

    it 'requires a signed-in user' do
      get '/recalls'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success for normal users' do
      get '/recalls', headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'limits the returned recalls for users with cancelled plans' do
      user = create(:user)
      user.refresh_access_token!

      get '/recalls', headers: auth_headers(user)
      expect(response).to have_http_status(:success)

      travel_to Time.now.end_of_day - 2.days do
        expire_all!(user)
      end
      get '/recalls', headers: auth_headers(user)
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)

      data = Recall.from_json({ recalls: json })
      data.each do |r|
        expect(r.publication_date).to be <= user.subscriptions.first.expiration
      end
    end

    it 'returns http success for administors' do
      get '/recalls', headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      get '/recalls', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns an array of documents' do
      count = [@sent.length, Constants::MAXIMUM_PAGE_SIZE].min
      get '/recalls', params: { limit: count }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      meta = json[:meta]
      expect(meta).to be_present
      expect(meta[:total]).to be_present
      expect(meta[:total]).to eq(@sent.length)

      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = Recall.from_json({ recalls: json })
      expect(data).to match_array(@sent.slice(0, count))
    end

    it 'returns the documents sorted by descending publication date' do
      count = [@sent.length, Constants::MAXIMUM_PAGE_SIZE].min
      get '/recalls', params: { limit: count }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = Recall.from_json({ recalls: json })
      prev_date = DateTime.tomorrow
      data.each do |r|
        expect(r.publication_date).to be <= prev_date
        prev_date = r.publication_date
      end
    end

    it 'returns a limited-size array of documents' do
      count = 5
      get '/recalls', params: { limit: count }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = Recall.from_json({ recalls: json })
      expect(data.sort).to match_array(@sent.slice(0, count))
    end

    it 'limits the documents returned to those available' do
      total = @sent.length
      count = [total, Constants::MAXIMUM_PAGE_SIZE].min
      offset = total - (Constants::MAXIMUM_PAGE_SIZE / 2)
      get '/recalls', params: { limit: count, offset: offset  }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(total - offset)

      data = Recall.from_json({ recalls: json })
      expect(data).to match_array(@sent.slice(offset, count))
    end

    it 'returns documents starting at the requested offset' do
      count = 5
      get '/recalls', params: { limit: count, offset: count }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = Recall.from_json({ recalls: json })
      expect(data).to match_array(@sent.slice(count, count))
    end

    it 'returns no documents if presented with an excessive offset' do
      count = 5
      get '/recalls', params: { limit: count, offset: @sent.length * 42 }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(0)
    end

    it 'limits negative offsets to available documents' do
      count = 5
      get '/recalls', params: { limit: count, offset: -42 }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(count)

      data = Recall.from_json({ recalls: json })
      expect(data).to match_array(@sent.slice(0, count))
    end

    it 'ignores a passed document total' do
      count = 5
      get '/recalls', params: { limit: count, offset: @sent.length * 42, total: @sent.length * 10000 }, headers: auth_headers(@user)

      json = JSON.parse(response.body).with_indifferent_access
      data = json[:data]
      expect(data).to be_a(Array)
      expect(data.length).to eq(0)
    end

    it 'returns only recalls with the specified IDs' do
      ids = Recall.limit(7).map{|r| r.id}
      recalls = fetch_all(:recalls, Recall, @user, 7, recalls: ids.join(','))
      expect(recalls.length).to eq(7)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'rejects invalid recall IDs' do
      ids = Recall.limit(21).map{|r| r.id}.each_with_index{|id, i| i % 2 ? id : nil}.compact
      expected_count = ids.length
      ids += ['not-really-a-legal-id', 'this-is-not-an-id-either']

      recalls = fetch_all(:recalls, Recall, @worker, expected_count, recalls: ids.join(','))
      expect(recalls.length).to eq(expected_count)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'ignores unknown recall IDs' do
      ids = Recall.limit(19).map{|r| r.id}.each_with_index{|id, i| i % 2 ? id : nil}.compact
      expected_count = ids.length
      ids += [Recall.generate_id('this'), Recall.generate_id('that')]

      recalls = fetch_all(:recalls, Recall, @worker, expected_count, recalls: ids.join(','))
      expect(recalls.length).to eq(expected_count)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'returns only recalls from the named feeds' do
      total = 50
      recalls = fetch_all(:recalls, Recall, @worker, total, names: 'fda,cpsc')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(['fda', 'cpsc']).to include(r.feed_name)
      end
    end

    it 'does not return recalls from non-public feeds to ordinary users' do
      total = @sent.length
      recalls = fetch_all(:recalls, Recall, @user, total)
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(FeedConstants::NONPUBLIC_NAMES).to_not include(r.feed_name)
      end
    end

    it 'only returns recalls published on or after the minimum date' do
      recalls = fetch_all(:recalls, Recall, @worker, @all.length)
      expect(recalls.length).to eq(@all.length)
      recalls.each do |r|
        expect(r.publication_date).to be >= Constants::MINIMUM_RECALL_DATE
      end
    end

    it 'limits recalls to those published on or after the minimum date' do
      recalls = fetch_all(:recalls, Recall, @worker, @all.length, after: Constants::MINIMUM_RECALL_DATE - 1.second)
      expect(recalls.length).to eq(@all.length)
      recalls.each do |r|
        expect(r.publication_date).to be >= Constants::MINIMUM_RECALL_DATE
      end
    end

    it 'returns only recalls published on or after a given date' do
      total = 45
      recalls = fetch_all(:recalls, Recall, @worker, total, after: @dates[44])
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[44]
      end
    end

    it 'returns only recalls published on or before a given date' do
      total = @dates.length - 45
      recalls = fetch_all(:recalls, Recall, @worker, total, before: @dates[45])
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(r.publication_date).to be <= @dates[45]
      end
    end

    it 'returns only sent recalls for normal users' do
      total = @sent.length
      recalls = fetch_all(:recalls, Recall, @user, total)
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(r).to be_sent
      end
    end

    it 'returns recalls with any status for workers' do
      total = @all.length
      recalls = fetch_all(:recalls, Recall, @worker, total)
      expect(recalls.length).to eq(total)
    end

    it 'returns unreviewed recalls for workers' do
      total = @unreviewed.length
      recalls = fetch_all(:recalls, Recall, @worker, total, state: 'unreviewed')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(r).to be_unreviewed
      end
    end

    it 'returns reviewed recalls for workers' do
      total = @reviewed.length
      recalls = fetch_all(:recalls, Recall, @worker, total, state: 'reviewed')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(r).to be_reviewed
      end
    end

    it 'returns only recalls affecting the requested groups' do
      total = 10
      recalls = fetch_all(:recalls, Recall, @worker, total, affects: 'children')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['children'] & r.affected).count).to be > 0
      end
    end

    it 'returns only recalls including the named allergerns' do
      total = 25
      recalls = fetch_all(:recalls, Recall, @worker, total, allergens: 'dairy,nuts')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['dairy', 'nuts'] & r.allergens).count).to be > 0
      end
    end

    it 'returns only recalls addressed to the supplied audience' do
      total = 15
      recalls = fetch_all(:recalls, Recall, @worker, total, audience: 'professionals')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['professionals'] & r.audience).count).to be > 0
      end
    end

    it 'returns only recalls including the named categories' do
      total = 60
      recalls = fetch_all(:recalls, Recall, @worker, total, categories: 'food')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['food'] & r.categories).count).to be > 0
      end
    end

    it 'returns only recalls including the named contaminants' do
      total = 15
      recalls = fetch_all(:recalls, Recall, @worker, total, contaminants: 'listeria,salmonella')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['listeria', 'salmonella'] & r.contaminants).count).to be > 0
      end
    end

    it 'returns only recalls including the named distribution' do
      total = 37
      recalls = fetch_all(:recalls, Recall, @worker, total, distribution: 'WA,ND')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['WA', 'ND'] & r.distribution).count).to be > 0
      end
    end

    it 'returns only recalls including the named risk' do
      total = 40
      recalls = fetch_all(:recalls, Recall, @worker, total, risk: 'probable,possible')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(['probable', 'possible']).to include(r.risk)
      end
    end

    it 'returns only recalls including the named sources' do
      total = 42
      recalls = fetch_all(:recalls, Recall, @worker, total, sources: 'fda,nhtsa')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(['fda', 'nhtsa']).to include(r.feed_source)
      end
    end

    it 'returns only recalls not affecting the requested groups' do
      total = 62
      recalls = fetch_all(:recalls, Recall, @worker, total, xaffects: 'children')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['children'] & r.affected).count).to eq(0)
      end
    end

    it 'returns only recalls not including the named allergens' do
      total = 47
      recalls = fetch_all(:recalls, Recall, @worker, total, xallergens: 'dairy,nuts')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['dairy', 'nuts'] & r.allergens).count).to eq(0)
      end
    end

    it 'returns only recalls not addressed to the supplied audience' do
      total = 57
      recalls = fetch_all(:recalls, Recall, @worker, total, xaudience: 'professionals')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['professionals'] & r.audience).count).to eq(0)
      end
    end

    it 'returns only recalls not including the named categories' do
      total = 12
      recalls = fetch_all(:recalls, Recall, @worker, total, xcategories: 'food')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['food'] & r.categories).count).to eq(0)
      end
    end

    it 'returns only recalls not including the named contaminants' do
      total = 57
      recalls = fetch_all(:recalls, Recall, @worker, total, xcontaminants: 'listeria,salmonella')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['listeria', 'salmonella'] & r.contaminants).count).to eq(0)
      end
    end

    it 'returns only recalls not including the named distribution' do
      total = 35
      recalls = fetch_all(:recalls, Recall, @worker, total, xdistribution: 'WA,ND')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect((['WA', 'ND'] & r.distribution).count).to eq(0)
      end
    end

    it 'returns only recalls not including the named risk' do
      total = 32
      recalls = fetch_all(:recalls, Recall, @worker, total, xrisk: 'probable,possible')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(['probable', 'possible']).to_not include(r.risk)
      end
    end

    it 'returns only recalls not including the named sources' do
      total = 61
      recalls = fetch_all(:recalls, Recall, @worker, total, xsources: 'cpsc,nhtsa')
      expect(recalls.length).to eq(total)
      recalls.each do |r|
        expect(['fda','usda']).to include(r.feed_source)
      end
    end

    it 'returns a summary of the latest recalls to normal users' do
      dates = @dates.slice(5...-8)
      after = dates.last.beginning_of_day.utc
      before = dates.first.end_of_day.utc

      recalls = Recall.in_published_order.was_sent.published_during(after, before)

      total = recalls.count

      risk = recalls.inject({}){|o, r| o[r.risk] = (o[r.risk] || 0) + 1; o}
      FeedConstants::RISK.each{|r| risk[r] = 0 if risk[r].blank?}
      risk.deep_symbolize_keys!

      categories = recalls.inject({}) do |o, r|
        r.categories.each{|c| o[c] = (o[c] || 0) + 1 if FeedConstants::PUBLIC_CATEGORIES.include?(c)};
        o
      end
      FeedConstants::PUBLIC_CATEGORIES.each{|c| categories[c] = 0 if categories[c].blank?}
      categories.deep_symbolize_keys!

      get '/recalls/summary', params: { after: after, before: before }, headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
      expect(response.body).to be_present

      summary = JSON.parse(response.body).deep_symbolize_keys[:data]
      expect(summary[:total]).to eq(total)
      expect(summary[:risk]).to eq(risk)
      expect(summary[:categories]).to eq(categories)
    end

    it 'returns a summary to workers' do
      get '/recalls/summary', headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
      expect(response.body).to be_present
    end

    it' returns a summary to admins' do
      get '/recalls/summary', headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
      expect(response.body).to be_present
    end

  end

  describe 'Create a Recall' do

    before :example do
      @recall = build(:recall,
        feed_name: 'fda',
        audience: FeedConstants::DEFAULT_AUDIENCE,
        categories: ['food'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: 'probable',
        state: 'unreviewed')
      @id = @recall.id
      @r = @recall.as_json(exclude_self_link: true)
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      Recall.destroy_all
    end

    it 'requires a signed-in user' do
      post '/recalls', params: { recall: @r }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'creates the document' do
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      r = Recall.find(@id) rescue nil
      expect(r).to be_present
    end

    it 'returns the document' do
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = Recall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      actual = filter_token(r.as_json(exclude_self_link: true)[:data])
      expected = filter_token(@r[:data])
      expect(actual).to eq(expected)
    end

    it 'uploads the document to S3' do
      recall_uploaded = false

      aws_helper = class_spy('AwsHelper')
      allow(AwsHelper).to receive(:upload_recall).with(@recall) { recall_uploaded = true }

      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)
      expect(recall_uploaded).to be true
    end

    it 'redirects if the document exists' do
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:see_other)
    end

    it 'ignores the passed id' do
      invalid_id = invalid_recall_id
      @r[:data][:id] = invalid_id.as_json
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = Recall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      r = Recall.find(@id) rescue nil
      expect(r).to be_present

      r = begin
            Recall.find(invalid_id)
          rescue Mongoid::Errors::DocumentNotFound
            nil
          end
      expect(r).to be_nil
    end

    it 'returns errors for invalid documents' do
      @r[:data][:attributes][:feedName] = nil
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Feed name ')
    end

    it 'handles no values at all' do
      post '/recalls', headers: auth_headers(@admin)

      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'does not send alerts for unreviewed recalls' do
      assert_no_enqueued_jobs
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs only: SendAlertsJob
    end

    it 'sends alerts for reviewed recalls' do
      assert_no_enqueued_jobs
      @r[:data][:attributes][:state] = 'reviewed'
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_enqueued_with(job: SendAlertsJob, args: ["send_recall_alerts"], queue: "alerts")
      assert_no_enqueued_jobs only: SendReviewNeededJob
    end

    it 'does not send alerts for sent recalls' do
      assert_no_enqueued_jobs
      @r[:data][:attributes][:state] = 'sent'
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs only: SendAlertsJob
    end

    it 'sends notification of unreviewed recalls' do
      assert_no_enqueued_jobs
      post '/recalls', params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_enqueued_jobs(0, queue: :alerts)
      assert_enqueued_jobs(1, only: SendReviewNeededJob, queue: :admin)
    end

  end

  describe 'Retrieve a single Recall' do

    before :example do
      @recall = create(:recall, feed_name: 'fda', state: 'sent')
      @nonpublic = FeedConstants::NONPUBLIC_NAMES.map{|fn| create(:recall, state: 'sent', feed_name: fn)}
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs
      Recall.destroy_all
    end

    it 'requires a signed-in user' do
      get "/recalls/#{@recall.id.as_json}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows reading if provided with the share token' do
      get "/recalls/#{@recall.id.as_json}/?token=#{@recall.token}"
      expect(response).to have_http_status(:success)
    end

    it 'reading via the share token increments the token accessed count' do
      token = @recall.share_token
      expect(token.access_count).to eq(0)

      get "/recalls/#{@recall.id.as_json}/?token=#{@recall.token}"
      expect(response).to have_http_status(:success)

      token.reload
      expect(token.access_count).to eq(1)
    end

    it 'reading wihtout the share token does not modify the token access count' do
      token = @recall.share_token
      expect(token.access_count).to eq(0)

      get "/recalls/#{@recall.id.as_json}", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)

      token.reload
      expect(token.access_count).to eq(0)
    end

    it 'rejects reading if provided with an illegal link token' do
      get "/recalls/#{@recall.id.as_json}/?token=#{BSON::ObjectId.new.to_s}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects reading with the token if the recall is not sent' do
      recall = create(:recall, state: 'reviewed')
      get "/recalls/#{recall.id.as_json}/?token=#{recall.token}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http success' do
      get "/recalls/#{@recall.id.as_json}", headers: auth_headers(@user)
      expect(response).to have_http_status(:success)
    end

    it 'returns the requested document' do
      get "/recalls/#{@recall.id.as_json}", headers: auth_headers(@user)

      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(Recall.from_json(json)).to eq(@recall)
    end

    it 'returns success during the grace period even if the recall is published after the user subscription expires' do
      user = create(:user, plan: Plan.all.find{|p| p.interval == 'month'})
      user.refresh_access_token!

      s = user.subscriptions.first
      expire_at(s)
      user.save!

      travel_to s.expiration - 1.minute do
        @recall.publication_date = Time.now
        @recall.save!
      end

      travel_to s.expiration + 1.day do
        user.refresh_access_token!
        get "/recalls/#{@recall.id.as_json}", headers: auth_headers(user)
        expect(response).to have_http_status(:success)
      end
    end

    it 'returns forbidden if the recall is published after the user subscription expires' do
      user = create(:user, plan: Plan.all.find{|p| p.interval == 'month'})
      user.refresh_access_token!

      s = user.subscriptions.first
      expire_at(s)
      user.save!

      travel_to s.expiration + 1.day do
        @recall.publication_date = Time.now
        @recall.save!

        user.refresh_access_token!
        get "/recalls/#{@recall.id.as_json}", headers: auth_headers(user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'returns an error for unknown documents' do
      get "/recalls/#{invalid_recall_id}", headers: auth_headers(@user)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'returns forbidden to ordinary users for non-public recalls' do
      @nonpublic.each do |r|
        get "/recalls/#{r.id.as_json}", headers: auth_headers(@user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'returns non-public recalls to adminstrators' do
      @nonpublic.each do |r|
        get "/recalls/#{r.id.as_json}", headers: auth_headers(@admin)
        expect(response).to have_http_status(:success)
      end
    end

    it 'returns non-public recalls to workers' do
      @nonpublic.each do |r|
        get "/recalls/#{r.id.as_json}", headers: auth_headers(@worker)
        expect(response).to have_http_status(:success)
      end
    end

  end

  describe 'Update a Recall' do

    before :example do
      @c = ['lead', 'salmonella']
      @recall = create(:recall,
        feed_name: 'fda',
        categories: ['food'],
        contaminants: @c,
        state: 'unreviewed')
      @id = @recall.id

      5.times do
        create(:recall,
                feed_name: 'fda',
                categories: ['food'],
                contaminants: @c,
                state: 'reviewed')
      end

      @prior = @recall.as_json
      @after = @recall.as_json
      @after[:data][:attributes][:contaminants] = []
    end

    after :example do
      clear_enqueued_jobs
      clear_performed_jobs

      Recall.destroy_all
    end

    it 'requires a signed-in user' do
      put "/recalls/#{@id.as_json}", params: { recall: @after }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      put "/recalls/#{@id.as_json}", params: { recall: @after }, as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      put "/recalls/#{@id.as_json}", params: { recall: @after }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      put "/recalls/#{@id.as_json}", params: { recall: @after }, as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns the document' do
      put "/recalls/#{@id.as_json}", params: { recall: @after }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = Recall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      expect(r.as_json[:data]).to eq(@after[:data])
    end

    it 'uploads the document to S3' do
      recall_uploaded = false

      aws_helper = class_spy('AwsHelper')
      allow(AwsHelper).to receive(:upload_recall).with(@recall) { recall_uploaded = true }

      put "/recalls/#{@id.as_json}", params: { recall: @after }, as: :json, headers: auth_headers(@admin)
      expect(recall_uploaded).to be true
    end

    it 'ignores the id within the document' do
      invalid_id = invalid_recall_id
      @after[:data][:id] = invalid_id.as_json
      put "/recalls/#{@id.as_json}", params: { recall: @after }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = Recall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      @after[:data][:id] = @id.as_json
      expect(r.as_json[:data]).to eq(@after[:data])
    end

    it 'returns errors for invalid documents' do
      @recall.feed_name = nil
      put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:conflict)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)

      error = errors.first
      expect(error[:status]).to be(409)
      expect(error[:detail]).to be_present
      expect(error[:detail]).to start_with('Feed name ')
    end

    it 'returns an error for unknown documents' do
      put "/recalls/#{invalid_recall_id}", params: { recall: @after }, as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

    it 'makes no changes when passed no values' do
      put "/recalls/#{@id.as_json}", params: { id: @id.as_json }, as: :json, headers: auth_headers(@admin)

      expect(response.body).to be_present

      r = Recall.from_json(response.body)
      expect(r).to be_valid
      expect(r.id).to eq(@id)

      expect(r.as_json[:data]).to eq(@prior[:data])
    end

    it 'does not send alerts for unreviewed recalls' do
      assert_no_enqueued_jobs
      put "/recalls/#{@id.as_json}", params: { recall: @r }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs
    end

    it 'sends alerts for reviewed recalls' do
      assert_no_enqueued_jobs
      @recall.state = 'reviewed'
      put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_enqueued_jobs(1, queue: :alerts)
    end

    it 'only sends alerts if no more recalls need reviewing' do
      assert_no_enqueued_jobs
      recall = create(:recall, state: 'unreviewed')

      expect(Recall.needs_review.count).to eq(2)

      @recall.state = 'reviewed'
      put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs

      recall.state = 'reviewed'
      put "/recalls/#{recall.id.as_json}", params: { recall: recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_enqueued_jobs(1, queue: :alerts)
    end

    it 'only sends alerts if alerts need sending' do
      assert_no_enqueued_jobs
      recall = create(:recall, state: 'unreviewed')

      expect(Recall.needs_review.count).to eq(2)

      recall.state = 'reviewed'
      put "/recalls/#{recall.id.as_json}", params: { recall: recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs

      recall.destroy
      Recall.needs_sending.each{|r| r.sent!}

      @recall.title = 'A new title'
      put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
      assert_no_enqueued_jobs
    end

    it 'requests the alerter to send recall alerts' do
      invoked = false
      allow(AwsHelper).to receive(:invoke) {|name, **args|
        expect(name).to eq(SendAlertsJob::ALERTER_FUNCTION)
        expect(**args).to eq(sendRecallAlerts: true)
        invoked = true
        true
      }

      Recall.needs_sending.each{|r| r.sent!}

      assert_no_enqueued_jobs

      perform_enqueued_jobs do
        @recall.state = 'reviewed'
        put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@admin)
        expect(response).to have_http_status(:success)
      end

      expect(invoked).to be true
      assert_performed_jobs(1)
    end

    it 'marking a recall sent returns http forbidden for normal users' do
      put "/recalls/#{@id.as_json}/sent", headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'marking a recall sent returns http success for administrators' do
      put "/recalls/#{@id.as_json}/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'marking a recall sent returns http success for workers' do
      put "/recalls/#{@id.as_json}/sent", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'marks the recall as sent' do
      expect(@recall).to_not be_sent

      put "/recalls/#{@id.as_json}/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      @recall.reload
      expect(@recall).to be_sent
    end

    it 'disallows workers to alter the state of a sent recall' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.state = 'reviewed'
      put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@user)

      expect(response).to have_http_status(:forbidden)
    end

    it 'disallows workers to alter the state of a sent recall' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.state = 'reviewed'
      put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@worker)

      expect(response).to have_http_status(:forbidden)
    end

    it 'allows admins to alter the state of a sent recall' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.state = 'reviewed'
      put "/recalls/#{@id.as_json}", params: { recall: @recall }, as: :json, headers: auth_headers(@admin)

      expect(response).to have_http_status(:success)
    end

    it 'uploads the document to S3 after marking sent' do
      recall_uploaded = false

      aws_helper = class_spy('AwsHelper')
      allow(AwsHelper).to receive(:upload_recall).with(@recall) { recall_uploaded = true }

      put "/recalls/#{@id.as_json}/sent", headers: auth_headers(@admin)
      expect(recall_uploaded).to be true
    end

    it 'marking all recalls sent returns http forbidden for normal users' do
      put "/recalls/sent", headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'marking all recalls sent returns http success for administrators' do
      put "/recalls/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'marking all recalls sent returns http success for workers' do
      put "/recalls/sent", headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'marks all recalls as sent' do
      expect(Recall.needs_sending.count).to eq(5)

      put "/recalls/sent", headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)

      expect(Recall.needs_sending.count).to eq(0)
    end

    it 'uploads all the documents to S3 after marking sent' do
      expected = Recall.needs_sending.count
      actual = 0

      aws_helper = class_spy('AwsHelper')
      Recall.needs_sending.each do |r|
        allow(AwsHelper).to receive(:upload_recall).with(r) { actual += 1 }
      end

      put "/recalls/sent", headers: auth_headers(@admin)
      expect(actual).to eq(expected)
    end

  end

  describe 'Delete a Recall' do

    before :example do
      @r = create(:recall)
    end

    after :example do
      Recall.destroy_all
    end

    it 'requires a signed-in user' do
      delete "/recalls/#{@r.id.as_json}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns http forbidden for normal users' do
      delete "/recalls/#{@r.id.as_json}", as: :json, headers: auth_headers(@user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns http success for administrators' do
      delete "/recalls/#{@r.id.as_json}", as: :json, headers: auth_headers(@admin)
      expect(response).to have_http_status(:success)
    end

    it 'returns http success for workers' do
      delete "/recalls/#{@r.id.as_json}", as: :json, headers: auth_headers(@worker)
      expect(response).to have_http_status(:success)
    end

    it 'returns http no content (204)' do
      delete "/recalls/#{@r.id.as_json}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:no_content)
    end

    it 'return only the head' do
      delete "/recalls/#{@r.id.as_json}", headers: auth_headers(@admin)

      expect(response.body).to be_blank
    end

    it 'returns an error for unknown documents' do
      delete "/recalls/#{invalid_recall_id}", headers: auth_headers(@admin)
      expect(response).to have_http_status(:not_found)

      errors = evaluate_error(response)
      expect(errors.length).to eq(1)
      expect(errors.first[:status]).to be(404)
    end

  end

end
