class Subscription
  include ActiveModel::Callbacks
  include Authority::Abilities
  include Mongoid::Document
  include Fields
  include Validations

  STATUS = %w(incomplete incomplete_expired trialing active past_due canceled unpaid)
  ACTIVE_STATUS = %w(incomplete active past_due)
  INACTIVE_STATUS = STATUS - ACTIVE_STATUS
  
  define_fields [
    { field: :_id, as: :id, type: BSON::ObjectId },

    # Note:
    # - These fields come from the Stripe
    # - expires_on is the *ACTUAL* subscripion expiration time
    #   Only compare it against Time.(end|start)_of_grace_period
    { field: :so, as: :started_on, type: Time, default: nil, outbound: true },
    { field: :ro, as: :renews_on,  type: Time, default: nil, outbound: true },
    { field: :xo, as: :expires_on, type: Time, default: nil, outbound: true },

    { field: :st, as: :status, type: String, default: nil, internal: true },

    { field: :si, as: :stripe_id, type: String, default: nil, internal: true },
    { field: :pi, as: :plan_id, type: String, default: nil, outbound: true },

    # Note:
    # - These fields do not come from Stripe
    { field: :rc, as: :recalls, type: Boolean, default: false, outbound: true },
    { field: :cv, as: :count_vins, type: Integer, default: 0, outbound: true },

    { field: :vk, as: :vkeys, type: Array, internal: true },

    # Note:
    # - Use :detect, and not :find, when searching since :find conflicts with MongoDB methods
    { embeds_many: :vins, store_as: :vn, outbound: true }
  ]

  embedded_in :user

  before_validation :normalize_times
  before_validation :promote_plan_attributes
  before_validation :ensure_vins
  before_validation :ensure_vkeys

  validates_datetime :started_on, allow_blank: false, on_or_before: :renews_on
  validates_datetime :renews_on, allow_blank: false
  validates_datetime :expires_on, allow_blank: false

  validates_inclusion_of :status, in: STATUS, allow_blank: false

  validates_presence_of :stripe_id, allow_blank: false
  validates_inclusion_of :plan_id, in: Plan.known_plans, allow_blank: false

  validates_numericality_of :count_vins, greater_than_or_equal_to: 0, only_integer: true

  validate :validate_vkeys

  class<<self

    def build_from_stripe(stripe_subscription)
      s = Subscription.new
      s.synchronize_with_stripe(stripe_subscription)
      s
    end

  end

  def synchronize_with_stripe(s)
    self.stripe_id = s.id
    self.plan_id = s.plan.id
    self.started_on = self.convert_stripe_time(s['start_date'] || s['start'], true)
    self.renews_on = self.convert_stripe_time(s.current_period_end)

    # Note:
    # - The predicate order matters
    #   Stripe fills different fields based on how the subscription changed
    self.expires_on = if s.ended_at.present?
                        self.convert_stripe_time(s.ended_at)
                      elsif s.cancel_at.present?
                        self.convert_stripe_time(s.cancel_at)
                      elsif s.canceled_at.present?
                        self.convert_stripe_time(s.canceled_at)
                      elsif INACTIVE_STATUS.include?(s.status)
                        self.normalize_time(Time.now)
                      elsif s.cancel_at_period_end
                        self.renews_on
                      else
                        Constants::FAR_FUTURE.start_of_grace_period
                      end

    self.status = s.status
  end

  def expiration
    self.expires_on.end_of_grace_period
  end

  def pi=(v)
    self[:pi] = v.is_a?(Plan) ? v.id : v
  end
  alias :plan_id= :pi=
  alias :plan= :pi=

  def plan
    Plan.from_id(self.plan_id)
  end

  def for_plan?(plan)
    self.plan_id == (plan.is_a?(Plan) ? plan.id : plan)
  end

  def for_stripe_id?(stripe_id)
    self.stripe_id == stripe_id
  end

  def active?(at_time=Time.now)
    at_time <= self.expires_on.end_of_grace_period
  end

  def inactive?(at_time=Time.now)
    !self.active?(at_time)
  end
  alias :is_expired? :inactive?

  def vin_from_id(id)
    return unless self.count_vins > 0
    (self.vins || []).detect{|v| v.id == id}
  end

  def vins?
    self.count_vins > 0
  end

  def as_json(*args, **options)
    plan = Plan.from_id(self.plan_id)
    json = super(plan.present? ? options.merge(related: plan) : options)
  end

  def <=>(other)
    return -1 unless other.is_a?(Subscription)
    self.expires_on <=> other.expires_on
  end

  protected

    def ensure_id
      super
      (self.vins || []).each{|v| v.send(:ensure_id)}
    end

    def ensure_vins
      self.vins = [] if self.vins.blank?
      while self.vins.length < self.count_vins do self.vins << Vin.new end
    end

    def ensure_vkeys
        self.vkeys = (self.vins || []).map{|v| v.to_vkey}.compact
    end

    def convert_stripe_time(t, at_start=false)
      self.normalize_time(Time.at(t), at_start)
    end

    def normalize_time(t, at_start=false)
      t.send(at_start ? :beginning_of_day : :end_of_day).beginning_of_minute.utc
    end

    def normalize_times
      self.started_on = self.normalize_time(self.started_on, true) if self.started_on_changed?
      self.renews_on = self.normalize_time(self.renews_on) if self.renews_on_changed?
      self.expires_on = self.normalize_time(self.expires_on) if self.expires_on_changed?
    end

    def promote_plan_attributes
      return unless self.plan_id_changed?

      plan = Plan.from_id(self.plan_id) unless self.plan_id.blank?
      if plan.blank?
        self.recalls = false
        self.count_vins = 0
        self.vins = []
      else
        self.recalls = plan.recalls
        self.count_vins = plan.vins
        self.vins ||= plan.vins > 0 ? plan.vins.times{ Vin.new } : []
      end
    end

    def validate_vkeys
      return unless self.vkeys.any?{|vkey| !Vehicles.valid_vkey?(vkey)}
      self.errors.add(:vkeys, 'contains one or more invalid keys')
    end

end
