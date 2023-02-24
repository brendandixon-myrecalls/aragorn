require 'rails_helper'

# Note:
# - Load only that needed to pass the tests; loading all the Helpers causes stack overflow issues
include ActionView::Helpers::SanitizeHelper

describe VehicleRecall, type: :model do

  def cleanse_text(t)
    strip_tags(t || '').squish
  end

  context 'Class' do

    after :example do
      VehicleRecall.destroy_all
    end

    it 'compares reviewed to equal reviewed' do
      expect(VehicleRecall.compare_recall_states('reviewed', 'reviewed')).to eq(0)
    end

    it 'compares sent to equal sent' do
      expect(VehicleRecall.compare_recall_states('sent', 'sent')).to eq(0)
    end

    it 'compares reviewed to be before sent' do
      expect(VehicleRecall.compare_recall_states('reviewed', 'sent')).to eq(-1)
    end

    it 'compares sent to be after reviewed' do
      expect(VehicleRecall.compare_recall_states('sent', 'reviewed')).to eq(1)
    end

    it 'ensures recalls for a given VIN exist' do
      expect(VehicleRecall.all.count).to eq(0)

      files = []
      Dir.glob('campaign*.json', base: NHTSA_BASIC_FOLDER) do |fn|
        files << JSON.parse(File.read(NHTSA_BASIC_FOLDER.join(fn)))
      end
      campaigns = files.map{|f| f['Results'].first['NHTSACampaignNumber']}
      expect(campaigns).to be_present

      vehicle = Vehicle.new({make: 'FauxMaker', model: 'FauxModel', year: 2000})
      expect(Vehicles::Basic).to receive(:vehicle_from_vin).with('fauxvin').and_return(vehicle)
      expect(Vehicles::Basic).to receive(:vehicle_campaigns).with(vehicle).and_return(campaigns)
      campaigns.each_with_index do |campaign_id, i|
        expect(Vehicles::Basic).to receive(:campaign_json).with(campaign_id).and_return(files[i])
      end

      expect(AwsHelper).to receive(:upload_recall).exactly(campaigns.length).with(any_args).and_return(true)
      VehicleRecall.ensure_vin_recalls('fauxvin')

      expect(VehicleRecall.all.count).to eq(campaigns.length)
      campaigns.each do |campaign_id|
        expect(VehicleRecall.for_campaigns(campaign_id)).to be_exists
      end
    end

    it 'creates from a campaign identifier' do
      Dir.glob('campaign*.json', base: NHTSA_FOLDER) do |fn|
        data = File.read(NHTSA_FOLDER.join('basic', fn))
        expect(Net::HTTP).to receive(:get).and_return(data)

        c = Vehicles::Basic.from_campaign_id('notused')
        expect(Vehicles::Basic).to receive(:from_campaign_id).with('notused')

        recall = VehicleRecall.from_campaign('notused')
        expect(recall).to be_valid

        expect(recall.campaign_id).to eq(c[:campaign_id])
        expect(recall.summary).to eq(c[:summary])
        expect(recall.consequence).to eq(c[:consequence])
        expect(recall.remedy).to eq(c[:remedy])
        expect(recall.publication_date).to eq(c[:publication_date])
        expect(recall.vehicles).to match(c[:vehicles])
        expect(recall.vkeys).to match(c[:vehicles.map{|v| Vehicles.vehicle_to_vkey(v)}])
      end
    end

    it 'creates the URI for the campaign page' do
      campaign_id = '16V741000'
      u = VehicleRecall.page_uri(campaign_id)
      expect(u.scheme).to eq('https')
      expect(u.query).to eq("nhtsaId=#{campaign_id}")
    end

  end

  context 'Validation' do

    before :example do
      vehicles = [
          { make: 'BMW', model: '3-SERIES', year: 2010 },
          { make: 'BMW', model: '5-SERIES', year: 2010 },
          { make: 'HONDA', model: 'ACCORD', year: 2010 },
      ].map{|h| build(:vehicle, make: h[:make], model: h[:model], year: h[:year])}

      @recall = build(:vehicle_recall,
        campaign_id: '16V741000',
        publication_date: Time.now.yesterday,
        summary: 'A summary',
        consequence: 'The consequence',
        remedy: 'The remedy',
        vehicles: vehicles,
        vkeys: vehicles.map{|v| v.to_vkey},
        state: 'reviewed')
    end

    it 'validates' do
      expect(@recall).to be_valid
    end

    it 'requires a campaign identifier' do
      @recall.campaign_id = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:campaign_id)
    end

    it 'requires a campaign identifier of the proper length' do
      @recall.campaign_id = '16V7410004'
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:campaign_id)

      @recall.campaign_id = '16V74100'
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:campaign_id)
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

    it 'requires a component' do
      @recall.component = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:component)
    end

    it 'requires a summary' do
      @recall.summary = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:summary)
    end

    it 'requires a consequence' do
      @recall.consequence = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:consequence)
    end

    it 'requires a remedy' do
      @recall.remedy = ''
      expect(@recall).to be_invalid
      expect(@recall.errors).to have_key(:remedy)
    end

    it 'ensures the vkeys match the vehicles' do
      @recall.vkeys = []
      expect(@recall).to be_valid
      expect(@recall.vkeys.length).to eq(@recall.vehicles.length)

      vkey = @recall.vkeys.pop
      expect(@recall).to be_valid
      expect(@recall.vkeys.length).to eq(@recall.vehicles.length)

      @recall.vkeys << vkey
      @recall.vehicles.pop
      expect(@recall).to be_valid
      expect(@recall.vkeys.length).to eq(@recall.vehicles.length)
    end

    it 'enforces a mimimum state' do
      @recall.state = nil
      expect(@recall).to be_valid
      expect(@recall.state).to eq(VehicleRecall::STATES.first)

      @recall.state = ''
      expect(@recall).to be_valid
      expect(@recall.state).to eq(VehicleRecall::STATES.first)
    end

    it 'allows legal states' do
      VehicleRecall::STATES.each do |state|
        @recall.state = state
        expect(@recall).to be_valid
      end
    end

    it 'disallows illegal states' do
      @recall.state = 'notastate'
      expect(@recall).to_not be_valid
      expect(@recall.errors).to have_key(:state)
    end

    it 'will merge errors from a nested vehicle' do
      v = @recall.vehicles.first
      v.year = Time.now.year + Vehicle::MAXIMUM_YEARS_HENCE + 1

      expect(@recall).to_not be_valid
      expect(@recall.merged_errors.full_messages.first).to start_with('Vehicle year ')
    end

  end

  context 'Behavior' do

    before :example do
      vehicles = [
          { make: 'BMW', model: '3-SERIES', year: 2010 },
          { make: 'BMW', model: '5-SERIES', year: 2010 },
          { make: 'HONDA', model: 'ACCORD', year: 2010 },
      ].map{|h| build(:vehicle, make: h[:make], model: h[:model], year: h[:year])}

      @recall = create(:vehicle_recall,
        campaign_id: '16V741000',
        publication_date: Time.now.yesterday,
        component: 'THE COMPONENT',
        summary: 'A summary',
        consequence: 'The consequence',
        remedy: 'The remedy',
        vehicles: vehicles,
        vkeys: vehicles.map{|v| v.to_vkey},
        state: 'reviewed')
    end

    after :example do
      VehicleRecall.destroy_all
    end

    it 'normalizes content' do
      expect(@recall.component).to eq('The Component')
    end

    it 'removes HTML tags from the summary' do
      @recall.summary = '<em>This has</em> some <strong>HTML tags that are </a>malformed.<div />'
      expect(@recall.summary).to eq('This has some HTML tags that are malformed.')
    end

    it 'removes HTML tags from the consequence' do
      @recall.consequence = '<em>This has</em> some <strong>HTML tags that are </a>malformed.<div />'
      expect(@recall.consequence).to eq('This has some HTML tags that are malformed.')
    end

    it 'removes HTML tags from the remedy' do
      @recall.remedy = '<em>This has</em> some <strong>HTML tags that are </a>malformed.<div />'
      expect(@recall.remedy).to eq('This has some HTML tags that are malformed.')
    end

    it 'transitions to sent when requested' do
      expect(@recall).to be_reviewed

      @recall.sent!
      expect(@recall).to be_sent
    end

    it 'transitions away from sent if requested' do
      @recall.sent!
      expect(@recall).to be_sent

      @recall.reviewed!
      expect(@recall).to be_reviewed
    end

  end

  context 'Scope Behavior' do

    before :all do
      # BSON::DateTime stores only milliseconds
      @dates = [-1.week.from_now.beginning_of_minute]
      @recalls = []
      @vkeys = {}

      10.times do |i|
        @recalls << create(:vehicle_recall,
                        publication_date: @dates.last,
                        state: 'reviewed')
        @recalls.last.vkeys.each do |vkey|
          @vkeys[vkey] ||= 0
          @vkeys[vkey] += 1
        end
        @dates << @dates.last - 1.day
      end

      15.times do |i|
        @recalls << create(:vehicle_recall,
                        publication_date: @dates.last,
                        state: 'sent')
        @recalls.last.vkeys.each do |vkey|
          @vkeys[vkey] ||= 0
          @vkeys[vkey] += 1
        end
        @dates << @dates.last - 1.day
      end

      expect(VehicleRecall.count).to eq(25)
    end

    after :all do
      VehicleRecall.destroy_all
    end

    it 'finds VehicleRecalls for the specified campaign' do
      @recalls.each do |r|
        vr = VehicleRecall.for_campaigns(r.campaign_id)
        expect(vr.count).to eq(1)
        expect(vr.first.campaign_id).to eq(r.campaign_id)
      end
    end

    it 'finds VehicleRecalls published on or after a date' do
      recalls = VehicleRecall.published_after(@dates[7])
      expect(recalls.count).to eq(8)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[7]
      end
    end

    it 'finds VehicleRecalls published on or before a date' do
      recalls = VehicleRecall.published_before(@dates[9])
      expect(recalls.count).to eq(16)
      recalls.each do |r|
        expect(r.publication_date).to be <= @dates[9]
      end
    end

    it 'finds VehicleRecalls published between dates' do
      recalls = VehicleRecall.published_during(@dates[12], @dates[4])
      expect(recalls.count).to eq(9)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[12]
        expect(r.publication_date).to be <= @dates[4]
      end
    end

    it 'finds VehicleRecalls published on a specified date' do
      recalls = VehicleRecall.published_on(@dates[3])
      expect(recalls.count).to eq(1)
      recalls.each do |r|
        expect(r.publication_date).to be >= @dates[3]
        expect(r.publication_date).to be <= @dates[3]
      end
    end

    it 'finds VehcileRecalls with the specified vkey' do
      @vkeys.each do |vkey, count|
        vr = VehicleRecall.for_vkeys(vkey)
        expect(vr.count).to eq(count)
        vr.each do |v|
          expect(v.vkeys).to include(vkey)
        end
      end
    end

    it 'finds reviewed VehicleRecalls' do
      recalls = VehicleRecall.needs_sending
      expect(recalls.count).to eq(10)
      recalls.each do |r|
        expect(r).to be_reviewed
      end
    end

    it 'finds sent VehicleRecalls' do
      recalls = VehicleRecall.was_sent
      expect(recalls.count).to eq(15)
      recalls.each do |r|
        expect(r).to be_sent
      end
    end

  end

end
