DATA_FOLDER = Rails.root.join('spec/data')
NHTSA_FOLDER = DATA_FOLDER.join('nhtsa')
NHTSA_BASIC_FOLDER = NHTSA_FOLDER.join('basic')
NHTSA_FULL_FOLDER = NHTSA_FOLDER.join('full')
RECALLS_FOLDER = DATA_FOLDER.join('recalls')
STRIPE_FOLDER = DATA_FOLDER.join('stripe')

def evaluate_error(response)
  expect(response.body).to be_present

  json = JSON.parse(response.body)
  expect(json).to be_a(Hash)

  json.deep_symbolize_keys!
  expect(json).to have_key(:errors)

  errors = json[:errors]
  expect(errors).to be_a(Array)
  expect(errors.length).to be > 0
  errors.each do |error|
    expect(error).to have_key(:status)
    expect(error).to have_key(:title)
  end

  errors
end

def fetch_all(path, model, user, expected_total, **params)

  params = params.merge({limit: Constants::MAXIMUM_PAGE_SIZE, offset: 0})
  collection = []

  loop do
    get "/#{path}", params: params, headers: auth_headers(user)
    expect(response).to have_http_status(:success)

    json = JSON.parse(response.body).with_indifferent_access
    meta = json[:meta]
    expect(meta).to be_present
    expect(meta[:total]).to be_present
    expect(meta[:total]).to eq(expected_total) if expected_total > 0

    data = json[:data]
    expect(data).to be_a(Array)
    break if data.length <= 0

    collection += model.from_json({ model._plural => json })
    params[:offset] += data.length
  end

  collection
end

def invalid_recall_id
  # Note: The route rejects identifiers that are not a stringized SHA256
  ('0' * 64).to_s
end

def auth_token(user)
  "Bearer #{user.access_token}"
end

def auth_headers(user)
  { 'Authorization' => auth_token(user) }
end

def expire_at(subscription, at_time=subscription.renews_on)
  subscription.expires_on = at_time
  subscription.status = 'canceled' if subscription.expires_on <= Time.now.end_of_day.beginning_of_minute
end

def expire_all!(user, at_time=Time.now)
  user.subscriptions.each{|s| expire_at(s, at_time) }
  user.save!
end

def reset_subscriptions!(user, keep_customer_id=true)
  user.customer_id = nil unless keep_customer_id
  user.subscriptions.clear
  user.save! unless user.new_record?
end

def make_faux_id(final = 'A')
  s = Constants::UPPERCASE + Constants::LOWERCASE + Constants::DIGITS
  (0...63).inject([]){|a, i| a << s[Helper.rand(s.length)]; a}.join + final
end

def purge_id(h)
  h.reject{|k, v| ['id', :id, '_id', :_id].include?(k) }
end

def read_nhtsa(fn, basic: true)
  File.read((basic ? NHTSA_BASIC_FOLDER : NHTSA_FULL_FOLDER).join(fn))
end

def read_stripe(fn)
  File.read(STRIPE_FOLDER.join(fn))
end

def load_stripe(fn)
  JSON.parse(read_stripe(fn), symbolize_names: true)
end

def generate_stripe_id(type)
  "faux-#{type}-#{Helper.generate_token}"
end

def select_from(values = [], n = 1, ensure_unique: false)
  return nil if values.blank?
  selection = []
  n = [n, 1].max
  n = [values.length, n].min

  raise Exception.new("Too many items to enforce unique selection") if n > values.length && ensure_unique

  return values if n == values.length && ensure_unique

  n.times do
    v = nil
    loop do
      v = values[Helper.rand(values.length)]
      break if !ensure_unique || !selection.include?(v)
    end
    selection << v
  end

  selection.present? ? selection : nil
end

def set_affected(categories = [])
  return ['children'] if categories.include?('toys')
  return ['seniors'] if categories.include?('drugs') && Helper.rand < 60
  return []
end

def set_allergens(categories = [])
  return [] unless FeedConstants.can_have_allergens?(categories)
  select_from(FeedConstants::FOOD_ALLERGENS, Helper.rand(3))
end

def set_categories(feed_name)
  allowed = FeedConstants.categories_for(feed_name)
  as_food = allowed & FeedConstants::CAN_HAVE_ALLERGENS_CATEGORIES
  if as_food.present? && Helper.rand < 70
    select_from(as_food)
  else
    select_from(allowed)
  end
end

def set_contaminants(categories = [])
  if FeedConstants.can_have_allergens?(categories)
    values = FeedConstants::FOOD_CONTAMINANTS
  elsif FeedConstants.acts_as_contaminable?(categories)
    values = FeedConstants::PRODUCT_CONTAMINANTS
  else
    values = []
  end
  select_from(values) || []
end

def set_feed_name
  # Note:
  # - Only use publicly accessible feeds (see FeedConstants::NONPUBLIC_NAMES)
  case Helper.rand
  when 00...45 then 'fda'
  when 45...70 then 'usda'
  when 70...95 then 'cpsc'
  else 'carseats'
  end
end

def set_date
  DateTime.now.beginning_of_day - Helper.rand(365).days
end

def set_risk(categories = [])
  if FeedConstants.can_have_allergens?(categories)
    Helper.rand < 65 ? 'possible' : 'probable'
  else
    Helper.rand < 20 ? 'possible' : 'none'
  end
end

def build_vehicle_list(count=Helper.rand(5)+2)
  vins = []
  count.times{|i| vins << select_vin(exclude_vins: vins) }
  vins.map{|v| build(:vehicle, vin: v)}
end

def select_vin(exclude_vins: [], exclude_vkeys: [])
  return select_from(TestConstants::VINS).first if exclude_vkeys.blank? && exclude_vins.blank?

  exclude_vins ||= []
  exclude_vkeys ||= []
  vins = TestConstants::VINS.filter do |vin|
    vh = Vehicle.new(TestConstants::VEHICLES[vin])
    !exclude_vins.include?(vin) && !exclude_vkeys.include?(vh.to_vkey)
  end
  return select_from(vins).first
end

def vkey_to_vin(vkey)
  TestConstants::VINS.find do |vin|
    v = TestConstants::VEHICLES[vin]
    vkey == Vehicles.generate_vkey(v[:make], v[:model], v[:year])
  end
end
