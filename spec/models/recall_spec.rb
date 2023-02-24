require 'rails_helper'

describe Recall, type: :model do

  def data_only(h)
    h = h.reject{|k, v| ['jsonapi', :jsonapi, 'links', :links, 'meta', :meta].include?(k) }
    h[:data] = h[:data].reject{|k, v| ['links', :links].include?(k) }
    h[:data][:attributes] = h[:data][:attributes].reject{|k, v| ['state', :state, 'token', :token].include?(k) }
    h
  end

  context 'JSON' do

    before :example do
      Recall.destroy_all
    end

    after :example do
      Recall.destroy_all
    end

    it 'loads received JSON' do
      Dir.glob(RECALLS_FOLDER.join('*.json')) do |filepath|
        s = File.read(RECALLS_FOLDER.join(filepath))
        expect(data_only(Recall.from_json(s).as_json)).to eq(JSON.parse(s).deep_symbolize_keys)
      end
    end

    it 'validates received JSON' do
      Dir.glob(RECALLS_FOLDER.join('*.json')) do |filepath|
        s = File.read(RECALLS_FOLDER.join(filepath))
        expect(Recall.from_json(s)).to be_valid
      end
    end

    it 'correctly saves / loads JSON to / from Mongo' do
      c = 0
      Dir.glob(RECALLS_FOLDER.join('*.json')) do |filepath|
        s = File.read(RECALLS_FOLDER.join(filepath))
        rc1 = Recall.from_json(s)
        rc1.save!
        rc2 = Recall.find(rc1.id)
        expect(rc2).to eq(rc1)
        c += 1
      end
      expect(Recall.count).to eq(c)
    end

    it 'includes the share token as an attibute' do
      r = create(:recall)
      j = r.as_json
      expect(j[:data][:attributes][:token]).to be_present
      expect(j[:data][:attributes][:token]).to eq(r.token)
    end

  end

  context 'Class' do

    it 'compares unreviewed to equal unreviewed' do
      expect(Recall.compare_recall_states('unreviewed', 'unreviewed')).to eq(0)
    end

    it 'compares reviewed to equal reviewed' do
      expect(Recall.compare_recall_states('reviewed', 'reviewed')).to eq(0)
    end

    it 'compares sent to equal sent' do
      expect(Recall.compare_recall_states('sent', 'sent')).to eq(0)
    end

    it 'compares unreviewed to be before reviewed' do
      expect(Recall.compare_recall_states('unreviewed', 'reviewed')).to eq(-1)
    end

    it 'compares unreviewed to be before sent' do
      expect(Recall.compare_recall_states('unreviewed', 'sent')).to eq(-1)
    end

    it 'compares reviewed to be before sent' do
      expect(Recall.compare_recall_states('reviewed', 'sent')).to eq(-1)
    end

    it 'compares reviewed to be after unreviewed' do
      expect(Recall.compare_recall_states('reviewed', 'unreviewed')).to eq(1)
    end

    it 'compares sent to be after reviewed' do
      expect(Recall.compare_recall_states('sent', 'reviewed')).to eq(1)
    end

  end

  context 'Validation' do

    before :example do
      @recall = build(:recall,
        feed_name: 'fda',
        publication_date: Time.now.yesterday,
        affected: nil,
        allergens: nil,
        categories: ['food'],
        contaminants: nil,
        distribution: USRegions::REGIONS[:west],
        risk: 'possible')
    end

    it 'validates' do
      expect(@recall).to be_valid
    end

    it 'allows legal feed names' do
      FeedConstants::NAMES.each do |fn|
        @recall.feed_name = fn
        @recall.categories = [FeedConstants.categories_for(fn).first]
        expect(@recall).to be_valid
      end
    end

    it 'disallows illegal feed names' do
      @recall.feed_name = 'not a feed'
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:feed_name)
    end

    it 'allows legal feed sources' do
      FeedConstants::SOURCES.each do |fs|
        @recall.feed_source = fs
        expect(@recall).to be_valid
      end
    end

    it 'disallows illegal feed sources' do
      @recall.feed_source = 'not a feed'
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:feed_source)
    end

    it 'requires a title' do
      @recall.title = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:title)
    end

    it 'allows a blank description' do
      @recall.description = ''
      expect(@recall).to be_valid

      @recall.description = nil
      expect(@recall).to be_valid
    end

    it 'requires a link' do
      @recall.link = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:link)
    end

    it 'requires the link to be a valid URI' do
      @recall.link = 'not a URI'
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:link)
    end

    it 'requires a publication date' do
      @recall.publication_date = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:publication_date)
    end

    it 'requires a publication date on or before midnight' do
      @recall.publication_date = DateTime.now.end_of_day + 5.seconds
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:publication_date)
    end

    it 'enforces a mimimum state' do
      @recall.state = nil
      expect(@recall).to be_valid
      expect(@recall.state).to eq('unreviewed')

      @recall.state = ''
      expect(@recall).to be_valid
      expect(@recall.state).to eq('unreviewed')
    end

    it 'allows legal states' do
      Recall::STATES.each do |state|
        @recall.state = state
        expect(@recall).to be_valid
      end
    end

    it 'disallows illegals states' do
      @recall.state = 'notastate'
      expect(@recall).to_not be_valid
      expect(@recall.errors).to have_key(:state)
    end

    it 'allows all affected' do
      FeedConstants::AFFECTED.each do |a|
        @recall.affected = [a]
        expect(@recall).to be_valid
      end
    end

    it 'disallows unknown affected' do
      @recall.affected = ['unknown']
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:affected)
    end

    it 'removes duplicate affected values' do
      v = FeedConstants::AFFECTED.first
      @recall.affected = [v, v]
      expect(@recall).to be_valid
      expect(@recall.affected).to match_array([v])
    end

    it 'allows allergens for food-like categories' do
      expect(Recall.categories_for('fda') & FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES).to eq(FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES)
      FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES.each do |ct|
        @recall.categories = [ct]
        FeedConstants::FOOD_ALLERGENS.each do |a|
          @recall.allergens = [a]
          expect(@recall).to be_valid
        end
      end
    end

    it 'disallows unknown allergens' do
      @recall.allergens = ['unknown']
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:allergens)
    end

    it 'removes duplicate allergen values' do
      v = FeedConstants::FOOD_ALLERGENS.first
      @recall.allergens = [v, v]
      expect(@recall).to be_valid
      expect(@recall.allergens).to match_array([v])
    end

    it 'allows all audiences' do
      FeedConstants::AUDIENCE.each do |a|
        @recall.audience = [a]
        expect(@recall).to be_valid
      end
    end

    it 'does not require an audience if unreviewed' do
      @recall.state = 'unreviewed'
      @recall.audience = nil
      expect(@recall).to be_valid
      expect(@recall.errors).to_not have_key(:audience)

      @recall.audience = []
      expect(@recall).to be_valid
      expect(@recall.errors).to_not have_key(:audience)
    end

    it 'validates the audience if provided even when unreviewed' do
      @recall.state = 'unreviewed'
      @recall.audience = ['unknown']
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:audience)
    end

    it 'requires an audience if reviewed' do
      @recall.state = 'reviewed'
      @recall.audience = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:audience)

      @recall.audience = []
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:audience)
    end

    it 'requires an audience if sent' do
      @recall.state = 'sent'
      @recall.audience = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:audience)

      @recall.audience = []
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:audience)
    end

    it 'disallows unknown audience' do
      @recall.audience = ['unknown']
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:audience)
    end

    it 'removes duplicate audience values' do
      v = FeedConstants::AUDIENCE.first
      @recall.audience = [v, v]
      expect(@recall).to be_valid
      expect(@recall.audience).to match_array([v])
    end

    it 'allows the categories for a name' do
      FeedConstants::NAMES.each do |name|
        @recall.feed_name = name
        Recall.categories_for(name).each do |ct|
          @recall.categories = [ct]
          expect(@recall).to be_valid
        end
      end
    end

    it 'disallows categories for another source' do
      (FeedConstants::CPSC_CATEGORIES - FeedConstants::FDA_CATEGORIES).each do |ct|
        @recall.categories = [ct]
        expect(@recall).to be_invalid
        expect(@recall.errors).to have_key(:categories)
      end
    end

    it 'disallows unknown categories' do
      @recall.categories = ['unknown']
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:categories)
    end

    it 'removes duplicate categories values' do
      v = Recall.categories_for('fda').first
      @recall.categories = [v, v]
      expect(@recall).to be_valid
      expect(@recall.categories).to match_array([v])
    end

    it 'does not require a categories if not reviewed' do
      @recall.state = 'unreviewed'
      @recall.categories = nil
      expect(@recall).to be_valid
    end

    it 'requires a categories if reviewed' do
      @recall.state = 'reviewed'
      @recall.categories = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:categories)
    end

    it 'requires a categories if sent' do
      @recall.state = 'sent'
      @recall.categories = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:categories)
    end

    it 'allows contaminants for food-like categories' do
      expect(Recall.categories_for('fda') & FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES).to eq(FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES)
      FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES.each do |ct|
        @recall.categories = [ct]
        FeedConstants::FOOD_CONTAMINANTS.each do |a|
          @recall.contaminants = [a]
          expect(@recall).to be_valid
        end
      end
    end

    it 'allows contaminants for product-like categories' do
      @recall.feed_name = 'cpsc'
      @recall.feed_source = 'cpsc'
      (Recall.categories_for('cpsc') & FeedConstants::ACTS_AS_CONTAMINABLE_CATEGORIES).each do |ct|
        @recall.categories = [ct]
        FeedConstants::PRODUCT_CONTAMINANTS.each do |a|
          @recall.contaminants = [a]
          expect(@recall).to be_valid
        end
      end
    end

    it 'disallows unknown contaminants' do
      @recall.contaminants = ['unknown']
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:contaminants)
    end

    it 'removes duplicate contaminants values' do
      v = FeedConstants::FOOD_CONTAMINANTS.first
      @recall.contaminants = [v, v]
      expect(@recall).to be_valid
      expect(@recall.contaminants).to match_array([v])
    end

    it 'does not require a distribution if not reviewed' do
      @recall.state = 'unreviewed'
      @recall.distribution = nil
      expect(@recall).to be_valid
    end

    it 'requires a distribution if reviewed' do
      @recall.state = 'reviewed'
      @recall.distribution = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:distribution)
    end

    it 'requires a distribution if sent' do
      @recall.state = 'sent'
      @recall.distribution = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:distribution)
    end

    it 'allows any state in the distribution' do
      USRegions::ALL_STATES.each do |state|
        @recall.distribution = [state]
        expect(@recall).to be_valid
      end
    end

    it 'removes duplicate distribution values' do
      v = USRegions::ALL_STATES.first
      @recall.distribution = [v, v]
      expect(@recall).to be_valid
      expect(@recall.distribution).to match_array([v])
    end

    it 'does not require a risk if not reviewed' do
      @recall.state = 'unreviewed'
      @recall.risk = nil
      expect(@recall).to be_valid
    end

    it 'requires a risk if reviewed' do
      @recall.state = 'reviewed'
      @recall.risk = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:risk)
    end

    it 'requires a risk if sent' do
      @recall.state = 'sent'
      @recall.risk = nil
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:risk)
    end

    it 'allows all risk' do
      FeedConstants::RISK.each do |r|
        @recall.risk = r
        expect(@recall).to be_valid
      end
    end

    it 'disallows unknown risk' do
      @recall.risk = 'unknown'
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:risk)
    end

  end

  context 'Behavior' do

    before :example do
      p = build(:preference,
        audience: FeedConstants::DEFAULT_AUDIENCE,
        categories: ['food'],
        distribution: USRegions::REGIONS[:west],
        risk: FeedConstants::DEFAULT_RISK)
      @user = create(:user, preference: p)

      @recall = create(:recall,
        feed_name: 'fda',
        audience: FeedConstants::DEFAULT_AUDIENCE,
        categories: ['food'],
        distribution: USRegions::REGIONS[:nationwide],
        risk: 'possible',
        state: 'unreviewed')
    end

    after :example do
      Recall.destroy_all
      User.destroy_all
    end

    it 'removes HTML tags from titles' do
      @recall.title = '<em>This has</em> some <strong>HTML tags that are </a>malformed.<div />'
      expect(@recall.title).to eq('This has some HTML tags that are malformed.')
    end

    it 'removes HTML tags from descriptions' do
      @recall.description = '<em>This has</em> some <strong>HTML tags that are </a>malformed.<div />'
      expect(@recall.description).to eq('This has some HTML tags that are malformed.')
    end

    it 'transitions to unreviewed when requested' do
      @recall.reviewed!
      expect(@recall).to be_reviewed

      @recall.unreviewed!
      expect(@recall).to be_unreviewed
    end

    it 'transitions to reviewed when requested' do
      expect(@recall).to be_unreviewed

      @recall.reviewed!
      expect(@recall).to be_reviewed
    end

    it 'transitions to sent when requested' do
      expect(@recall).to be_unreviewed

      @recall.sent!
      expect(@recall).to be_sent
    end

    it 'transitions away from sent when requested' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.reviewed!
      expect(@recall).to be_reviewed
    end

  end

  context 'Helpers' do

    before :example do
      @recall = create(:recall, risk: 'probable')
      (0..2).each{ create(:recall, risk: 'probable')}
      (0..4).each{ create(:recall, risk: 'possible')}
      (0..5).each{ create(:recall, risk: 'none')}
    end

    after :example do
      Recall.destroy_all
    end

    it 'acknowledges it is contaminable' do
      FeedConstants::ACTS_AS_CONTAMINABLE_CATEGORIES.each do |ct|
        @recall.categories = ct
        expect(@recall).to be_acts_as_contaminable
      end
    end

    it 'acknowledges it is food' do
      FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES.each do |ct|
        @recall.categories = ct
        expect(@recall).to be_can_have_allergens
      end
    end

    it 'acknowleges it is for an audience' do
      FeedConstants::AUDIENCE.each do |au|
        @recall.audience = au
        expect(@recall.for_audience?(au)).to be true
      end
    end

    FeedConstants::AUDIENCE.each do |au|
      class_eval <<-METHODS, __FILE__, __LINE__+1
        it 'acknowledges it is for #{au}' do
          @recall.audience = au
          expect(@recall.for_#{au}?).to be true
        end
      METHODS
    end

    it 'acknowledges it is for all audiences' do
        @recall.audience = FeedConstants::AUDIENCE
        expect(@recall.for_audience?(FeedConstants::AUDIENCE)).to be true
    end

    it 'rejects unreviewed recalls as needing to be sent' do
      @recall.unreviewed!
      expect(@recall).to_not be_needs_sending
    end

    it 'acknowledges reviewed recalls need sending' do
      @recall.reviewed!
      expect(@recall).to be_needs_sending
    end

    it 'rejects sent recalls as needing to be sent' do
      @recall.sent!
      expect(@recall).to_not be_needs_sending
    end

    it 'acknowledges recalls whose alerts should be sent by email' do
      @recall.risk = 'probable'
      expect(@recall).to be_should_send_email

      @recall.risk = 'possible'
      expect(@recall).to be_should_send_email
    end

    it 'acknowledges recalls whose alerts should not be sent by email' do
      @recall.risk = 'none'
      expect(@recall).to_not be_should_send_email
    end

    it 'acknowledges recalls whose alerts should be sent by phone' do
      @recall.risk = 'probable'
      expect(@recall).to be_should_send_phone
    end

    it 'acknowledges recalls whose alerts should not be sent by phone' do
      @recall.risk = 'possible'
      expect(@recall).to_not be_should_send_phone

      @recall.risk = 'none'
      expect(@recall).to_not be_should_send_phone
    end

    it 'distinguishes high risk recalls' do
      Recall.all.each do |r|
        expect(r).to be_high_risk if r.risk == 'probable'
        expect(r).to_not be_high_risk if r.risk != 'probable'
      end
    end

  end

  context 'Scope Behavior' do

    before :all do
      @dates = []

      # BSON::DateTime stores only milliseconds
      @dates << -1.week.from_now.beginning_of_minute
      5.times do |i|
        create(:recall,
          feed_name: 'usda',
          publication_date: @dates.last,
          state: 'unreviewed',
          affected: [],
          allergens: ['dairy', 'nuts'],
          audience: ['consumers'],
          categories: ['food'],
          contaminants: ['salmonella'],
          distribution: USRegions::REGIONS[:west],
          risk: 'probable')
      end

      @dates << -3.days.from_now.beginning_of_minute
      4.times do |i|
        create(:recall,
          feed_name: 'fda',
          publication_date: @dates.last,
          state: 'reviewed',
          affected: ['seniors'],
          allergens: [],
          audience: ['consumers'],
          categories: ['food', 'drugs'],
          contaminants: ['listeria', 'salmonella'],
          distribution: USRegions::REGIONS[:northeast],
          risk: 'possible')
      end

      @dates << -2.days.from_now.beginning_of_minute
      3.times do |i|
        create(:recall,
          feed_name: 'cpsc',
          publication_date: @dates.last,
          state: 'unreviewed',
          affected: ['children'],
          allergens: [],
          audience: ['professionals'],
          categories: ['toys'],
          contaminants: [],
          distribution: USRegions::REGIONS[:midwest],
          risk: 'none')
      end

      @dates << -1.day.from_now.beginning_of_minute
      2.times do |i|
        create(:recall,
          feed_name: 'carseats',
          publication_date: @dates.last,
          state: 'sent',
          affected: [],
          allergens: [],
          audience: ['consumers', 'professionals'],
          categories: ['home'],
          contaminants: [],
          distribution: USRegions::REGIONS[:southwest],
          risk: 'none')
      end

      expect(Recall.count).to eq(14)
    end

    after :all do
      Recall.destroy_all
    end

    it 'finds Recalls with the specified IDs' do
      ids = Recall.limit(11).map{|r| r.id}

      recalls = Recall.has_id(ids)
      expect(recalls.count).to eq(11)
      expect(recalls.uniq{|r| r.id}.length).to eq(11)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'rejects illegal Recall IDs from the search' do
      ids = Recall.limit(7).map{|r| r.id}
      ids += ['an invalid id', 'yet another invalid id']

      recalls = Recall.has_id(ids)
      expect(recalls.count).to eq(7)
      expect(recalls.uniq{|r| r.id}.length).to eq(7)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'ignores unknown Recall IDs' do
      ids = Recall.limit(7).map{|r| r.id}
      ids += [Recall.generate_id('foo'), Recall.generate_id('bar')]

      recalls = Recall.has_id(ids)
      expect(recalls.count).to eq(7)
      expect(recalls.uniq{|r| r.id}.length).to eq(7)
      recalls.each do |r|
        expect(ids).to include(r.id)
      end
    end

    it 'finds Recalls from a requested feed' do
      recalls = Recall.from_feed('fda')
      expect(recalls.count).to eq(4)
      recalls.each do |r|
        expect(r.feed_name).to eq('fda')
      end
    end

    it 'finds Recalls from the requested feeds' do
      recalls = Recall.from_feeds(['fda', 'cpsc'])
      expect(recalls.count).to eq(7)
      recalls.each do |r|
        expect(['fda', 'cpsc']).to include(r.feed_name)
      end
    end

    it 'finds Recalls from a requested source' do
      recalls = Recall.from_source('cpsc')
      expect(recalls.count).to eq(3)
      recalls.each do |r|
        expect(r.feed_source).to eq('cpsc')
      end
    end

    it 'finds Recalls published on or after a date' do
      recalls = Recall.published_after(@dates[2])
      expect(recalls.count).to eq(5)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[2]
      end
    end

    it 'finds Recalls published on or before a date' do
      recalls = Recall.published_before(@dates[1])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect(r.publication_date).to be <= @dates[1]
      end
    end

    it 'finds Recalls published between dates' do
      recalls = Recall.published_during(@dates[1], @dates[2])
      expect(recalls.count).to eq(7)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[1]
        expect(r.publication_date).to be <= @dates[2]
      end
    end

    it 'finds Recalls published on a specified date' do
      recalls = Recall.published_on(@dates[3])
      expect(recalls.count).to eq(2)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[3]
        expect(r.publication_date).to be <= @dates[3]
      end
    end

    it 'finds Recalls with specified affected' do
      recalls = Recall.includes_affected(['children', 'seniors'])
      expect(recalls.count).to eq(7)
      recalls.each do |r|
        expect((r.affected & ['children', 'seniors']).length).to eq(1)
      end
    end

    it 'finds Recalls without any of the specified affected' do
      recalls = Recall.excludes_affected(['seniors'])
      expect(recalls.count).to eq(10)
      recalls.each do |r|
        expect((r.affected & ['seniors']).length).to eq(0)
      end
    end

    it 'finds Recalls with all requested affected' do
      recalls = Recall.has_all_affected(['children', 'seniors'])
      expect(recalls.count).to eq(0)

      recalls = Recall.has_all_affected(['children'])
      expect(recalls.count).to eq(3)
      recalls.each do |r|
        expect((r.affected & ['children']).length).to eq(1)
      end
    end

    it 'finds Recalls with specified allergens' do
      recalls = Recall.includes_allergens(['eggs', 'nuts'])
      expect(recalls.count).to eq(5)
      recalls.each do |r|
        expect((r.allergens & ['eggs', 'nuts']).length).to eq(1)
      end
    end

    it 'finds Recalls without any of the specified allergens' do
      recalls = Recall.excludes_allergens(['dairy'])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect((r.allergens & ['dairy']).length).to eq(0)
      end
    end

    it 'finds Recalls with all requested allergens' do
      recalls = Recall.has_all_allergens(['eggs', 'nuts'])
      expect(recalls.count).to eq(0)

      recalls = Recall.has_all_allergens(['dairy', 'nuts'])
      expect(recalls.count).to eq(5)
      recalls.each do |r|
        expect((r.allergens & ['dairy', 'nuts']).length).to eq(2)
      end
    end

    it 'finds Recalls for the specified audience' do
      recalls = Recall.includes_audience(['consumers'])
      expect(recalls.count).to eq(11)
      recalls.each do |r|
        expect((r.audience & ['consumers']).length).to eq(1)
      end

      recalls = Recall.includes_audience(['professionals'])
      expect(recalls.count).to eq(5)
      recalls.each do |r|
        expect((r.audience & ['professionals']).length).to eq(1)
      end
    end

    it 'finds Recalls without any of the specified audience' do
      recalls = Recall.excludes_audience(['consumers'])
      expect(recalls.count).to eq(3)
      recalls.each do |r|
        expect((r.audience & ['consumers']).length).to eq(0)
      end
    end

    it 'finds Recalls for all requested audiences' do
      recalls = Recall.has_all_audience(['consumers', 'professionals'])
      expect(recalls.count).to eq(2)
      recalls.each do |r|
        expect((r.audience & ['consumers', 'professionals']).length).to eq(2)
      end
    end

    it 'finds Recalls with specified categories' do
      recalls = Recall.includes_categories(['food', 'home'])
      expect(recalls.count).to eq(11)
      recalls.each do |r|
        expect((r.categories & ['food', 'home']).length).to eq(1)
      end
    end

    it 'finds Recalls without any of the specified categories' do
      recalls = Recall.excludes_categories(['toys', 'home'])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect((r.categories & ['toys', 'home']).length).to eq(0)
      end
    end

    it 'finds Recalls with all requested categories' do
      recalls = Recall.has_all_categories(['food', 'home'])
      expect(recalls.count).to eq(0)

      recalls = Recall.has_all_categories(['food', 'drugs'])
      expect(recalls.count).to eq(4)
      recalls.each do |r|
        expect((r.categories & ['food', 'drugs']).length).to eq(2)
      end
    end

    it 'finds Recalls with specified contaminants' do
      recalls = Recall.includes_contaminants(['lead', 'salmonella'])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect((r.contaminants & ['lead', 'salmonella']).length).to eq(1)
      end
    end

    it 'finds Recalls without any of the specified contaminants' do
      recalls = Recall.excludes_contaminants(['listeria'])
      expect(recalls.count).to eq(10)
      recalls.each do |r|
        expect((r.contaminants & ['listeria']).length).to eq(0)
      end
    end

    it 'finds Recalls with all requested contaminants' do
      recalls = Recall.has_all_contaminants(['lead', 'salmonella'])
      expect(recalls.count).to eq(0)

      recalls = Recall.has_all_contaminants(['listeria', 'salmonella'])
      expect(recalls.count).to eq(4)
      recalls.each do |r|
        expect((r.contaminants & ['listeria', 'salmonella']).length).to eq(2)
      end
    end

    it 'finds Recalls with specified distribution' do
      regions = USRegions::REGIONS[:west] + USRegions::REGIONS[:southeast]
      recalls = Recall.includes_distribution(regions)
      expect(recalls.count).to eq(5)
      recalls.each do |r|
        expect((r.distribution & regions).length).to eq(USRegions::REGIONS[:west].length)
      end
    end

    it 'finds Recalls without any of the specified distribution' do
      recalls = Recall.excludes_distribution(['MN', 'OR'])
      expect(recalls.count).to eq(6)
      recalls.each do |r|
        expect((r.distribution & ['MN', 'OR']).length).to eq(0)
      end
    end

    it 'finds Recalls with all requested distribution' do
      regions = USRegions::REGIONS[:west] + USRegions::TERRITORIES
      recalls = Recall.has_all_distribution(regions)
      expect(recalls.count).to eq(0)

      regions = USRegions::REGIONS[:west]
      recalls = Recall.has_all_distribution(regions)
      expect(recalls.count).to eq(5)
      recalls.each do |r|
        expect((r.distribution & regions).length).to eq(regions.length)
      end
    end

    it 'finds Recalls from the specified feeds' do
      recalls = Recall.includes_names(['fda', 'usda'])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect(([r.feed_name] & ['fda', 'usda']).length).to eq(1)
      end
    end

    it 'finds Recalls not from the specified feeds' do
      recalls = Recall.excludes_names(['fda'])
      expect(recalls.count).to eq(10)
      recalls.each do |r|
        expect(([r.feed_name] & ['fda']).length).to eq(0)
      end
    end

    it 'finds Recalls with specified risk' do
      recalls = Recall.includes_risk(['probable', 'possible'])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect(([r.risk] & ['probable', 'possible']).length).to eq(1)
      end
    end

    it 'finds Recalls without any of the specified risk' do
      recalls = Recall.excludes_risk(['none'])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect(([r.risk] & ['none']).length).to eq(0)
      end
    end

    it 'finds Recalls from the specified sources' do
      recalls = Recall.includes_sources(['fda', 'nhtsa'])
      expect(recalls.count).to eq(6)
      recalls.each do |r|
        expect(([r.feed_source] & ['fda', 'nhtsa']).length).to eq(1)
      end
    end

    it 'finds Recalls not from the specified sources' do
      recalls = Recall.excludes_sources(['fda'])
      expect(recalls.count).to eq(10)
      recalls.each do |r|
        expect(([r.feed_source] & ['fda']).length).to eq(0)
      end
    end

    it 'finds unreviewed Recalls' do
      recalls = Recall.needs_review
      expect(recalls.count).to eq(8)
      recalls.each do |r|
        expect(r).to be_unreviewed
      end
    end

    it 'finds reviewed Recalls' do
      recalls = Recall.needs_sending
      expect(recalls.count).to eq(4)
      recalls.each do |r|
        expect(r).to be_reviewed
      end
    end

    it 'finds sent Recalls' do
      recalls = Recall.was_sent
      expect(recalls.count).to eq(2)
      recalls.each do |r|
        expect(r).to be_sent
      end
    end

  end

end
