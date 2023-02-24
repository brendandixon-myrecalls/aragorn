require 'rails_helper'

describe 'Plan', type: :model do

  describe 'Class Methods' do

    it 'returns the plans' do
      plans = Plan.all
      expect(plans).to be_an(Array)
      expect(plans.length).to be > 0
      plans.each {|p| expect(p).to be_a(Plan) }
    end

    it 'returns plans by identifier' do
      Plan.all.each do |plan|
        expect(Plan.from_id(plan.id)).to be(plan)
      end
    end

    it 'returns plans by plan' do
      Plan.all.each do |plan|
        expect(Plan.from_id(plan)).to be(plan)
      end
    end

    it 'returns nil for unknown plan identifiers' do
      expect(Plan.from_id('notaplan')).to be_nil
    end

    it 'returns all known plan identifiers' do
      known = Plan.known_plans
      expect(known).to be_is_a(Array)
      expect(known.length).to eq(Plan.all.length)
      Plan.all.each do |c|
        expect(known).to include(c.id)
      end
    end

  end

  describe 'Validation' do

    before :example do
      @plan = Plan.from_json(Plan.all.first.as_json, all_fields: true)
    end

    it 'validates well-formed plans' do
      expect(@plan).to be_valid
    end

    it 'requires an id' do
      @plan.instance_variable_set(:@id, nil)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:id)
    end

    it 'requires a name' do
      @plan.instance_variable_set(:@name, nil)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:name)
    end

    it 'requires a name of a minimum size' do
      @plan.instance_variable_set(:@name, 'xxx')
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:name)
    end

    it 'requires an amount' do
      @plan.instance_variable_set(:@amount, nil)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:amount)
    end

    it 'requires an amount greater than zero' do
      @plan.instance_variable_set(:@amount, 0)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:amount)

      @plan.instance_variable_set(:@amount, -42)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:amount)
    end

    it 'requires an interval' do
      @plan.instance_variable_set(:@interval, nil)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:interval)
    end

    it 'accepts all recognized plan intervals' do
      Plan::INTERVALS.each do |interval|
        @plan.instance_variable_set(:@interval, interval)
        expect(@plan).to be_valid
      end
    end

    it 'rejects unrecognized plan intervals' do
      @plan.instance_variable_set(:@interval, 'notaninterval')
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:interval)
    end

    it 'requires recalls to be true or false' do
      @plan.instance_variable_set(:@recalls, true)
      expect(@plan).to be_valid

      @plan.instance_variable_set(:@recalls, false)
      expect(@plan).to be_valid

      @plan.instance_variable_set(:@recalls, 'nottrueorfalse')
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:recalls)
    end

    it 'requires the VIN count to be greater than or equal to zero' do
      @plan.instance_variable_set(:@vins, 42)
      expect(@plan).to be_valid

      @plan.instance_variable_set(:@vins, 0)
      expect(@plan).to be_valid

      @plan.instance_variable_set(:@vins, -42)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:vins)
    end

    it 'requires the VIN count to be an integer' do
      @plan.instance_variable_set(:@vins, 42.5)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:vins)
    end

    it 'allows both the recalls feature and a non-zero VIN count' do
      @plan.instance_variable_set(:@recalls, true)
      @plan.instance_variable_set(:@vins, 42)
      expect(@plan).to be_valid
    end

    it 'requires either the recalls feature or a non-zero VIN count' do
      @plan.instance_variable_set(:@recalls, true)
      @plan.instance_variable_set(:@vins, 0)
      expect(@plan).to be_valid

      @plan.instance_variable_set(:@recalls, false)
      @plan.instance_variable_set(:@vins, 42)
      expect(@plan).to be_valid

      @plan.instance_variable_set(:@recalls, false)
      @plan.instance_variable_set(:@vins, 0)
      expect(@plan).to_not be_valid
      expect(@plan.errors).to have_key(:base)
    end

  end

  describe 'Behavior' do

    it 'returns the duration for month-long plans' do
      plan = Plan.from_json(Plan.all.first.as_json, all_fields: true)
      plan.instance_variable_set(:@interval, 'month')
      expect(plan.duration).to eq(1.month)
    end

    it 'returns the duration for year-long plans' do
      plan = Plan.from_json(Plan.all.first.as_json, all_fields: true)
      plan.instance_variable_set(:@interval, 'year')
      expect(plan.duration).to eq(1.year)
    end

    it 'converts plans to JSON' do
      Plan.all.each do |plan|
        json = plan.as_json[:data]
        expect(json[:id]).to eq(plan.id)

        json = json[:attributes]
        expect(json[:name]).to eq(plan.name)
        expect(json[:amount]).to eq(plan.amount)
        expect(json[:interval]).to eq(plan.interval)
        
        expect(json[:recalls]).to eq(plan.recalls)
        expect(json[:recalls].to_s).to match(plan.for_recalls? ? Constants::TRUE_PATTERN : Constants::FALSE_PATTERN)
        
        expect(json[:vins]).to eq(plan.vins)
        expect(json[:vins].to_s).to match(/\d+/)
      end

    end

    it 'validates Stripe plans on creation' do
      json = load_stripe('plans.json').first
      json['id'] = nil
      sp = Stripe::Plan.construct_from(json)
      expect { Plan.from_stripe_plan(sp) }.to raise_error(ActiveModel::ValidationError)
    end

    it 'considers plans equal if their attributes are equal' do
      Plan.all.each do |p|
        expect(p).to eq(Plan.from_json(p.as_json, all_fields: true))
      end
    end

    it 'sorts plans by name' do
      prev = ''
      Plan.all.sort.each do |p|
        expect(p.name).to be > prev
        prev = p.name
      end
    end

  end

end
