class Vin
  include ActiveModel::Callbacks
  include Authority::Abilities
  include Mongoid::Document
  include Fields
  include Validations

  MINIMUM_UPDATE_MONTHS = 6

  self.authorizer_name = 'SubscriptionAuthorizer'
  
  define_fields [
    { field: :_id, as: :id, type: BSON::ObjectId },

    { field: :vin, type: String, default: nil },
    { field: :ut,  as: :updated_at, type: Time, default: Constants::DISTANT_PAST, internal: true },
    { field: :update_allowed_on, type: Time, synthetic: true },

    { field: :rv, as: :reviewed, type: Boolean, default: false, outbound: true },

    { field: :cp, as: :campaigns, type: Array },

    { embeds_one: :vehicle, store_as: :vh, autobuild: true },
  ]

  embedded_in :subscription

  validates_is_vin :vin, allow_blank: true

  validate :check_vehicle
  validate :validate_campaigns

  def recalls
    return [] if self.vehicle.blank?
    self.vehicle.recalls
  end

  def subscription
    self._parent
  end

  def allow_updates?
    self.update_allowed_on <= Time.now.end_of_day
  end

  def update_allowed_on
    (self.updated_at || Constants::DISTANT_PAST) + MINIMUM_UPDATE_MONTHS.months
  end

  def vin=(vin)
    return if self[:vin] == vin
    self[:vin] = vin
    self.campaigns = []
    self.vehicle.reset unless self.has_vin?
  end

  def to_vkey
    return if self.vehicle.blank?
    self.vehicle.to_vkey
  end

  def <=>(other)
    return 1 unless other.is_a?(Vin)
    return 1 if self.vehicle.present? && other.vehicle.blank?
    return -1 if self.vehicle.blank? && other.vehicle.present?
    return self.vehicle <=> other.vehicle unless self.vehicle.blank? || self.vehicle == other.vehicle
    self.vin <=> other.vin
  end

  unless Rails.env.production?
    def reset
      self.campaigns = []
      self.reviewed = false
      self.updated_at = Constants::DISTANT_PAST
      self.vin = nil
      self.vehicle = nil
    end
  end

  protected

    def check_vehicle
      if self.has_vin? && self.vehicle.blank?
        self.errors.add(:base, 'vehicle is required when the VIN is present')
      elsif !self.has_vin? && self.vehicle.present?
        self.errors.add(:base, 'vehicle is disallowed if the VIN is missing or invalid')
      end
    end

    def ensure_id
      super
      self.vehicle.send(:ensure_id) if self.vehicle.present?
    end

    def has_vin?
      self.vin.present? && Vehicles.valid_vin?(self.vin)
    end

    def validate_campaigns
      return unless self.campaigns.present?
      if self.vin.blank?
        self.errors.add(:campaigns, 'requires a valid VIN')
      elsif self.campaigns.any?{|c| !c.is_a?(String) || !c.match?(Vehicles::CAMPAIGN_REGEX) }
        self.errors.add(:campaigns, 'must contain only valid NHTSA campaign identifiers')
      end
    end

end
