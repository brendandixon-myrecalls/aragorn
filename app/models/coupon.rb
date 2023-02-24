class Coupon
  include ActiveModel::Attributes
  include ActiveModel::AttributeAssignment
  include ActiveModel::Model
  include ActiveModel::Validations
  include Fields

  # Note:
  # - Stripe allows 'once' and 'repeating' in addition to 'forever'
  DURATIONS = ['forever']

  FIELDS = [
    { field: :_id, as: :id, type: String, outbound: true },
    { field: :name, type: String, outbound: true },
    { field: :duration, type: String, outbound: true },
    { field: :amount_off, type: Integer, outbound: true },
    { field: :percent_off, type: Float, outbound: true }
  ]

  FIELDS.each do |f|
    attribute f[:as] || f[:field], f[:type]
    attr_accessor f[:as] || f[:field]
  end
  alias :_id :id

  define_fields FIELDS

  validates_presence_of :id
  validates_length_of :name, minimum: 4, allow_blank: false
  validates_inclusion_of :duration, in: DURATIONS, allow_blank: false
  validates_numericality_of :amount_off, greater_than: 0, only_integer: true, allow_nil: true
  validates_numericality_of :percent_off, greater_than: 0, less_than_or_equal_to: 100, only_integer: false, allow_nil: true
  validate :validate_discount

  class<<self

    def all
      @@all ||= begin
        StripeHelper.coupons.map{|c| Coupon.from_stripe_coupon(c)}
      rescue Exception=>e
        Rails.logger.error "Unable to load Stripe coupons: #{e}"
        []
      end
    end

    def free_forever
      @@free_forever ||= self.all.detect{|c| c.percent_off >= 100 }
    end

    def from_id(coupon_id)
      coupon_id = coupon_id.id if coupon_id.is_a?(Coupon)
      self.all.find{|c| c.id == coupon_id}
    end

    def from_stripe_coupon(coupon)
      c = Coupon.new({
        id: coupon.id,
        name: coupon.name,
        duration: coupon.duration,
        amount_off: coupon.amount_off,
        percent_off: coupon.percent_off,
      })
      c.validate!
      c
    end

    def known_coupons
      @@known_coupons ||= self.all.map{|c| c.id}
    end

  end

  def attributes
    FIELDS.inject({}){|h, f| h[f[:field]] = self.send(f[:field]); h}
  end

  def as_json(*args, **options)
    super(args, options.merge(exclude_self_link: true))
  end

  def ==(other)
    return false unless other.is_a?(Coupon)
    self.attributes == other.attributes
  end
  alias :eql? :==

  def hash
    FIELDS.map{|f| self.send(f[:field])}.hash
  end

  def <=>(other)
    return -1 unless other.is_a?(Coupon)
    self.name <=> other.name
  end

  protected

    def validate_discount
      return if self.amount_off.present? || self.percent_off.present?
      self.errors.add(:base, 'Either amount_off or percent_off must be present')
    end

end
