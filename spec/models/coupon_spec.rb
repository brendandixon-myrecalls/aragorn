require 'rails_helper'

describe 'Coupon', type: :model do

  describe 'Class Methods' do

    it 'returns the coupons' do
      coupons = Coupon.all
      expect(coupons).to be_an(Array)
      expect(coupons.length).to be > 0
      coupons.each {|c| expect(c).to be_a(Coupon) }
    end

    it 'returns coupons by identifier' do
      Coupon.all.each do |coupon|
        expect(Coupon.from_id(coupon.id)).to be(coupon)
      end
    end

    it 'returns coupons by coupon' do
      Coupon.all.each do |coupon|
        expect(Coupon.from_id(coupon)).to be(coupon)
      end
    end

    it 'returns nil for unknown coupon identifiers' do
      expect(Coupon.from_id('notacoupon')).to be_nil
    end

    it 'returns all known coupon identifiers' do
      known = Coupon.known_coupons
      expect(known).to be_is_a(Array)
      expect(known.length).to eq(Coupon.all.length)
      Coupon.all.each do |c|
        expect(known).to include(c.id)
      end
    end

  end

  describe 'Validation' do

    before :example do
      @coupon = Coupon.from_json(Coupon.all.first.as_json, all_fields: true)
    end

    it 'validates well-formed coupons' do
      expect(@coupon).to be_valid
    end

    it 'requires an id' do
      @coupon.instance_variable_set(:@id, nil)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:id)
    end

    it 'requires a name' do
      @coupon.instance_variable_set(:@name, nil)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:name)
    end

    it 'requires a name of a minimum size' do
      @coupon.instance_variable_set(:@name, 'xxx')
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:name)
    end

    it 'requires a duration' do
      @coupon.instance_variable_set(:@duration, nil)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:duration)
    end

    it 'accepts all recognized coupon durations' do
      Coupon::DURATIONS.each do |duration|
        @coupon.instance_variable_set(:@duration, duration)
        expect(@coupon).to be_valid
      end
    end

    it 'rejects unrecognized coupon durations' do
      @coupon.instance_variable_set(:@duration, 'notanduration')
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:duration)
    end

    it 'does not require an amount off' do
      @coupon.instance_variable_set(:@amount_off, nil)
      @coupon.instance_variable_set(:@percent_off, 42)
      expect(@coupon).to be_valid
    end

    it 'accepts an amount off' do
      @coupon.instance_variable_set(:@amount_off, 42)
      expect(@coupon).to be_valid
    end

    it 'requires the amount off to be greater than zero' do
      @coupon.instance_variable_set(:@amount_off, 0)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:amount_off)

      @coupon.instance_variable_set(:@amount_off, -42)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:amount_off)
    end

    it 'requires the amount off to be greater an integer' do
      @coupon.instance_variable_set(:@amount_off, 42.5)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:amount_off)
    end

    it 'does not require an percent off' do
      @coupon.instance_variable_set(:@amount_off, 42)
      @coupon.instance_variable_set(:@percent_off, nil)
      expect(@coupon).to be_valid
    end

    it 'accepts an percent off' do
      @coupon.instance_variable_set(:@percent_off, 42)
      expect(@coupon).to be_valid
    end

    it 'requires the percent off to be greater than zero' do
      @coupon.instance_variable_set(:@percent_off, 0)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:percent_off)

      @coupon.instance_variable_set(:@percent_off, -42)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:percent_off)
    end

    it 'requires the percent off to be less than or equal to 100' do
      @coupon.instance_variable_set(:@percent_off, 100.1)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:percent_off)
    end

    it 'does not require the percent off to be an integer' do
      @coupon.instance_variable_set(:@percent_off, 42.5)
      expect(@coupon).to be_valid
    end

    it 'requires either an amount off or a percent off' do
      @coupon.instance_variable_set(:@amount_off, nil)
      @coupon.instance_variable_set(:@percent_off, nil)
      expect(@coupon).to_not be_valid
      expect(@coupon.errors).to have_key(:base)
    end

  end

  describe 'Behavior' do

    it 'converts coupons to JSON' do
      Coupon.all.each do |coupon|
        json = coupon.as_json[:data]
        expect(json[:id]).to eq(coupon.id)

        json = json[:attributes]
        expect(json[:name]).to eq(coupon.name)
        expect(json[:duration]).to eq(coupon.duration)
        expect(json[:amountOff]).to eq(coupon.amount_off)
        expect(json[:percentOff]).to eq(coupon.percent_off)
      end

    end

    it 'validates Stripe coupons on creation' do
      json = load_stripe('coupons.json').first
      json['id'] = nil
      sc = Stripe::Coupon.construct_from(json)
      expect { Coupon.from_stripe_coupon(sc) }.to raise_error(ActiveModel::ValidationError)
    end

    it 'considers coupons equal if their attributes are equal' do
      Coupon.all.each do |c|
        expect(c).to eq(Coupon.from_json(c.as_json, all_fields: true))
      end
    end

    it 'sorts coupons by name' do
      prev = ''
      Coupon.all.sort.each do |c|
        expect(c.name).to be > prev
        prev = c.name
      end
    end

  end

end
