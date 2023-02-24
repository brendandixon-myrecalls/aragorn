class Vehicle
  include ActiveModel::Callbacks
  include Authority::Abilities
  include Mongoid::Document
  include Fields
  include Validations

  MAXIMUM_YEARS_HENCE = 5

  define_fields [
    { field: :_id, as: :id, type: BSON::ObjectId },

    { field: :mk,  as: :make,  type: String,  default: nil },
    { field: :mo,  as: :model, type: String,  default: nil },
    { field: :yr,  as: :year,  type: Integer, default: nil },
  ]

  embedded_in :vehicle_recall, polymorphic: true
  embedded_in :vin, polymorphic: true

  validates_format_of :make, with: Vehicles::MAKE_REGEX, allow_blank: true
  validates_format_of :model, with: Vehicles::MODEL_REGEX, allow_blank: true
  validates_is_year :year, min: Constants::MINIMUM_VEHICLE_YEAR, max: lambda{|r| Time.now.year+MAXIMUM_YEARS_HENCE }, allow_blank: true

  validate :require_all_or_none

  def blank?
    self.make.blank? && self.model.blank? && (self.year.blank? || 0)
  end

  def present?
    !self.blank?
  end

  def recalls
    VehicleRecall.for_vkeys(self.to_vkey)
  end

  def reset
    self.make =
    self.model =
    self.year = nil
  end

  def to_vkey
    Vehicles.generate_vkey(self.make, self.model, self.year)
  end

  def ==(other)
    return false unless other.is_a?(Vehicle)
    self.make == other.make && self.model == other.model && self.year == other.year
  end
  alias :eql? :==

  def hash
    [self.make, self.model, self.year].hash
  end

  def <=>(other)
    return -1 unless other.is_a?(Vehicle)
    return self.year <=> other.year unless self.year == other.year
    return self.make <=> other.make unless self.make == other.make
    self.model <=> other.model unless self.model == other.model
  end

  protected

    def require_all_or_none
      return unless self.errors.empty?
      return if self.make.present? == self.model.present? && self.make.present? == self.year.present?
      self.errors.add(:base, "make, model, and year are all required")
    end

end
