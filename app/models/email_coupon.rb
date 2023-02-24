class EmailCoupon
  include ActiveModel::Callbacks
  include Mongoid::Document
  include Fields
  include Validations
  include Emailable

  define_fields [
    { field: :em, as: :email, type: String },
    { field: :ci, as: :coupon_id, type: String },
  ]

  index({em: 1}, {sparse: true, unique: true})
  index({ci: 1}, sparse: true)
  
  validates_inclusion_of :coupon_id, in: Coupon.known_coupons, allow_blank: false

  scope :in_email_order, lambda{|asc=true| self.order_by(email: asc ? 1 : -1)}

  scope :for_coupon, lambda{|coupon| self.where(coupon_id: coupon.is_a?(Coupon) ? coupon.id : (coupon || ''))}
  scope :for_email, lambda{|email| self.where(email: email)}

  class<<self

    def coupon_for_email(email)
      self.for_email(email).first.coupon rescue nil
    end

  end

  def ci=(v)
    self[:ci] = v.is_a?(Coupon) ? v.id : v
  end
  alias :coupon_id= :ci=
  alias :coupon= :ci=

  def coupon
    @coupon ||= Coupon.from_id(self.coupon_id)
  end

  def as_json(*args, **options)
    return super(args, options) if options[:exclude_related]

    options.delete(:exclude_related)
    super(args, options.merge(related: self.coupon))
  end

end
