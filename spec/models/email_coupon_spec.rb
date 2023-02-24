require 'rails_helper'

describe EmailCoupon, type: :model do

  context 'Validation' do

    before :example do
      @user = create(:user, count_subscriptions: 0)
      @ec = build(:email_coupon, email: @user.email, coupon_id: Coupon.known_coupons.first)
    end

    after :example do
      EmailCoupon.destroy_all
      User.destroy_all
    end

    it 'validates' do
      expect(@ec).to be_valid
    end

    it 'requires an email address' do
      @ec.email = ''
      expect(@ec).to be_invalid
      expect(@ec.errors).to have_key(:email)

      @ec.email = nil
      expect(@ec).to be_invalid
      expect(@ec.errors).to have_key(:email)
    end

    it 'accepts known coupons and coupon identifiers' do
      Coupon.all.each do |c|
        @ec.coupon_id = c
        expect(@ec).to be_valid

        @ec.coupon_id = c.id
        expect(@ec).to be_valid
      end
    end

    it 'rejects unknown coupons' do
      @ec.coupon_id = 'notacoupon'
      expect(@ec).to_not be_valid
      expect(@ec.errors).to have_key(:coupon_id)
    end

  end

  context 'Behavior' do

    before :example do
      @user = create(:user, count_subscriptions: 0)
      @ec = create(:email_coupon, email: @user.email, coupon: Coupon.free_forever)
    end

    after :example do
      EmailCoupon.destroy_all
      User.destroy_all
    end

    it 'returns the coupon for a known email address' do
      expect(EmailCoupon.coupon_for_email(@user.email)).to eq(@ec.coupon)
    end

    it 'returns nil for unknown email addresses' do
      expect(EmailCoupon.coupon_for_email('notanemail@address.com')).to be_blank
    end

  end

  context 'Scope Behavior' do

    before :all do
      @users = (0...10).map{|i| create(:user, count_subscriptions: 0)}
      @users.slice(0,5).each{|u| create(:email_coupon, email: u.email, coupon_id: Coupon.known_coupons.first)}
      @users.slice(5,5).each{|u| create(:email_coupon, email: u.email, coupon_id: Coupon.known_coupons.second)}

      expect(EmailCoupon.count).to eq(10)
    end

    after :all do
      EmailCoupon.destroy_all
      User.destroy_all
    end

    it 'returns the email coupons in ascending email order by default' do
      prev = EmailCoupon.in_email_order.first.email
      EmailCoupon.in_email_order.each do |ec|
        expect(ec.email).to be >= prev
        prev = ec.email
      end
    end

    it 'returns the email coupons in ascending email order' do
      prev = EmailCoupon.in_email_order(true).first.email
      EmailCoupon.in_email_order(true).each do |ec|
        expect(ec.email).to be >= prev
        prev = ec.email
      end
    end

    it 'returns the email coupons in descending email order' do
      prev = EmailCoupon.in_email_order(false).first.email
      EmailCoupon.in_email_order(false).each do |ec|
        expect(ec.email).to be <= prev
        prev = ec.email
      end
    end

    it 'returns the email coupons for a given coupon' do
      Coupon.known_coupons.slice(0,2).each do |c|
        expect(EmailCoupon.for_coupon(c).count).to eq(5)
        EmailCoupon.for_coupon(c).each do |ec|
          expect(ec.coupon_id).to eq(c)
        end
      end
    end

  end

end
