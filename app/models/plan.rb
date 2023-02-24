class Plan
  include ActiveModel::Attributes
  include ActiveModel::AttributeAssignment
  include ActiveModel::Model
  include ActiveModel::Validations
  include Fields

  # Note:
  # - Stripe supports 'day' and 'week' as well as 'month' and 'year'
  INTERVALS = %w(month year)

  FIELDS = [
    { field: :_id, as: :id, type: String, outbound: true },
    { field: :name, type: String, outbound: true },
    { field: :amount, type: Integer, outbound: true },
    { field: :interval, type: String, outbound: true },
    { field: :recalls, type: Boolean, outbound: true },
    { field: :vins, type: Integer, outbound: true }
  ]

  FIELDS.each do |f|
    attribute f[:as] || f[:field], f[:type]
    attr_accessor f[:as] || f[:field]
  end
  alias :_id :id

  define_fields FIELDS

  validates_presence_of :id
  validates_length_of :name, minimum: 4, allow_blank: false
  validates_numericality_of :amount, greater_than: 0, only_integer: true, allow_nil: false
  validates_inclusion_of :interval, in: INTERVALS, allow_blank: false
  validates_inclusion_of :recalls, in: [true, false], allow_blank: false
  validates_numericality_of :vins, greater_than_or_equal_to: 0, only_integer: true, allow_nil: false
  validate :validate_features

  class<<self

    def all
      @@all ||= begin
        StripeHelper.plans.map{|p| Plan.from_stripe_plan(p)}
      rescue Exception=>e
        Rails.logger.error "Unable to load Stripe plans: #{e}"
        []
      end
    end

    def yearly_all
      @@yearly_all ||= self.all.detect{|p| p.recalls && p.vins > 0 && p.yearly?}
    end

    def yearly_recalls
      @@yearly_recalls ||= self.all.detect{|p| p.recalls && p.vins <= 0 && p.yearly?}
    end

    def yearly_vins
      @@yearly_vins ||= self.all.detect{|p| !p.recalls && p.vins > 0 && p.yearly?}
    end

    def from_id(plan_id)
      plan_id = plan_id.id if plan_id.is_a?(Plan)
      self.all.find{|p| p.id == plan_id}
    end

    def from_stripe_plan(plan)
        metadata = plan.metadata || {}
        p = Plan.new({
          id: plan.id,
          amount: plan.amount,
          interval: plan.interval,
          name: plan.nickname,
          recalls: (metadata[:recalls] || '') =~ /true/ ? true : false,
          vins: (metadata[:vins] =~ /\d+/ ? metadata[:vins] : '').to_i
        })
        p.validate!
        p
    end

    def known_plans
      @@known_plans ||= self.all.map{|p| p.id}
    end

  end

  def attributes
    FIELDS.inject({}){|h, f| h[f[:field]] = self.send(f[:field]); h}
  end

  INTERVALS.each do |interval|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def #{interval+'ly'}?
        self.interval == '#{interval}'
      end
    METHODS
  end

  def duration
    1.send(self.interval)
  end

  def for_recalls?
    self.recalls
  end

  def for_vehicles?
    self.vins.is_a?(Integer) && self.vins > 0
  end

  def as_json(*args, **options)
    super(args, options.merge(exclude_self_link: true))
  end

  def ==(other)
    return false unless other.is_a?(Plan)
    self.attributes == other.attributes
  end
  alias :eql? :==

  def hash
    FIELDS.map{|f| self.send(f[:field])}.hash
  end

  def <=>(other)
    return -1 unless other.is_a?(Plan)
    self.name <=> other.name
  end

  protected

    def validate_features
      return if self.recalls == true || self.vins > 0
      self.errors.add(:base, 'Recalls or VINs must be part of a plan')
    end

end
