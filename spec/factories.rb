# To use FactoryBot within in the console:
#     rails console -e test --sandbox
#     require "factory_bot"
#     require "./factories"
#     include FactoryBot::Syntax::Methods
# See https://www.rubydoc.info/gems/factory_bot/file/GETTING_STARTED.md
#

require Rails.root.join('spec', 'test_constants')
require Rails.root.join('spec', 'test_helpers')

def add_factories
  include FactoryBot::Syntax::Methods
end
alias :af :add_factories

FactoryBot.define do

  factory :email_coupon do
    sequence(:email) {|n| "member#{'%04d' % n}@nomail.com" }
    coupon_id { Coupon.known_coupons.first }
  end

  factory :preference do

    alert_for_vins { true }
    send_vin_summaries { true }

    alert_by_email { Helper.rand < 75 }
    alert_by_phone { true }
    send_summaries { Helper.rand < 60 }

    audience { FeedConstants::DEFAULT_AUDIENCE }
    categories {
      case Helper.rand
      when 00...40 then FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES + ['home', 'electronics', 'toys']
      when 40...55 then select_from(FeedConstants::CPSC_CATEGORIES, Helper.rand(4))
      when 55...70 then select_from(FeedConstants::ACTS_AS_CONTAMINABLE_CATEGORIES, Helper.rand(5))
      else select_from(FeedConstants::PUBLIC_CATEGORIES, Helper.rand(6))
      end
    }
    sequence(:distribution, TestConstants::REGIONS) {|region| USRegions::REGIONS[region] }

    risk {
      case Helper.rand
      when 00..60 then FeedConstants::TEXTED_RISK
      when 60..90 then FeedConstants::ALERTED_RISK
      else ['possible']
      end
    }
  end

  factory :recall do
    feed_name { set_feed_name }
    feed_source { FeedConstants.source_for(feed_name) }

    sequence(:title) {|n| "The #{n.ordinalize} Recall" }
    description { 'This is a recall description.' }

    sequence(:link) {|n| "http://foo.com?press_release=#{n}" }

    publication_date { set_date }
    state { 'reviewed' }

    categories { set_categories(feed_name) }

    affected { set_affected(categories) }
    allergens { set_allergens(categories) }
    audience { FeedConstants::DEFAULT_AUDIENCE }
    contaminants { set_contaminants(categories) }
    sequence(:distribution, TestConstants::REGIONS) {|region| USRegions::REGIONS[region] }
    risk { set_risk(categories) }
  end

  factory :share_token do
    recall_id { Recall.random_id }
  end

  factory :subscription do
    transient do
      plan { Plan.yearly_all }
      count_vins { nil }
    end

    started_on { Time.now }
    renews_on { started_on + plan.duration }
    expires_on { renews_on < Time.now ? renews_on : Constants::FAR_FUTURE.start_of_grace_period }
    status { expires_on < Time.now ? 'canceled' : 'active' }

    stripe_id { generate_stripe_id(:subscription) }
    plan_id { plan.id }

    recalls { plan.recalls }
    vins { (0...(count_vins || plan.vins)).map{build(:vin)} }
  end

  factory :user do
    transient do
      plan { nil }
      plan_start { nil }
      count_subscriptions { 1 }
      count_vins { nil }
    end

    sequence(:first_name) {|n| "Jill#{n}" }
    last_name { "Recaller" }

    sequence(:email) {|n| "member#{'%04d' % n}@nomail.com" }
    sequence(:phone, 1000) do |n|
      case Helper.rand
      when 00...85 then "123.555.#{n}"
      else nil
      end
    end

    password { "pa$$W0rdpa$$W0rd" }
    role { 'member' }

    email_confirmed_at { set_date }
    email_confirmation_sent_at { nil }
    phone_confirmed_at { email_confirmed_at }
    phone_confirmation_sent_at { nil }

    reset_password_sent_at { nil }
    locked_at { nil }

    factory :admin do
      sequence(:first_name) {|n| n > 0 ? "A#{n}" : 'A'}
      last_name { "Admin" }
      email { "#{first_name.downcase}.#{last_name.downcase}@nomail.com" }
      email_confirmed_at { DateTime.now - 1.year }
      phone_confirmed_at { email_confirmed_at }
      role { 'admin' }
    end

    factory :worker do
      sequence(:first_name) {|n| n > 0 ? "A#{n}" : 'A'}
      last_name { "Worker" }
      email { "#{first_name.downcase}.#{last_name.downcase}@nomail.com" }
      email_confirmed_at { DateTime.now - 1.year }
      phone_confirmed_at { email_confirmed_at }
      role { 'worker' }
    end

    preference { build :preference }

    customer_id { generate_stripe_id(:customer) if role == 'member' && count_subscriptions > 0}
    subscriptions do
      (0...count_subscriptions).map do |i|
        p = (i == 0 ? (plan || Plan.yearly_all) : Plan.yearly_vins)
        cv = count_vins || p.vins
        build(:subscription, plan: p, started_on: plan_start || Time.now, count_vins: cv)
      end if customer_id.present?
    end
  end

  factory :vehicle do
    transient do
      vin { select_vin }
    end

    make { TestConstants::VEHICLES[vin][:make] }
    model { TestConstants::VEHICLES[vin][:model] }
    year { TestConstants::VEHICLES[vin][:year] }
  end

  factory :vin do
    vin { select_vin }

    updated_at { Time.now.beginning_of_day if vin.present? }
    vehicle { build(:vehicle, vin: vin) if vin.present? }
    reviewed { vehicle.present? }
  end

  factory :vehicle_recall do
    sequence(:campaign_id) {|n| format("16V741%03d", n)}

    publication_date { set_date }
    component { 'The Component'}
    summary { 'A vehicle got recalled' }
    consequence { 'Dangerous things could occur' }
    remedy { 'It should be fixed' }

    vehicles { build_vehicle_list }
    vkeys { vehicles.map{|v| Vehicles.generate_vkey(v.make, v.model, v.year)} }

    state { 'reviewed' }
  end

end
