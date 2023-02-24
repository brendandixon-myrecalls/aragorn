class User
  include ActiveModel::Callbacks
  include ActiveModel::SecurePassword
  include Authority::UserAbilities
  include Authority::Abilities
  include Mongoid::Document
  include Mongoid::Timestamps::Short
  include Mongoid::Locker
  include BCrypt
  include Fields
  include Validations
  include Emailable
  include Phoneable

  define_fields [
    { field: :_id, as: :id, type: BSON::ObjectId },

    { field: :lln, as: :locker_locking_name, type: String, internal: true },
    { field: :lla, as: :locker_locked_at, type: Time, internal: true },

    { field: :fn, as: :first_name, type: String },
    { field: :ln, as: :last_name, type: String },

    { field: :em, as: :email, type: String },
    { field: :ph, as: :phone, type: String },

    { field: :ro, as: :role, type: String, default: 'member' },

    { field: :password, type: String, inbound: true },
    { field: :ep, as: :password_digest, type: String, internal: true },
    { field: :at, as: :access_token, type: String, internal: true },

    ## Confirmable
    { field: :eca, as: :email_confirmed_at, type: Time, default: nil, internal: true },
    { field: :ecs, as: :email_confirmation_sent_at, type: Time, default: nil, internal: true },
    { field: :ect, as: :email_confirmation_token, type: String, internal: true },
    { field: :ee,  as: :email_errors, type: Integer, default: 0, internal: true },
    { field: :email_suspended, type: Boolean, synthetic: true },
    { field: :email_confirmed, type: Boolean, synthetic: true },

    { field: :pca, as: :phone_confirmed_at, type: Time, default: nil, internal: true },
    { field: :pcs, as: :phone_confirmation_sent_at, type: Time, default: nil, internal: true },
    { field: :pct, as: :phone_confirmation_token, type: String, internal: true },
    { field: :phone_confirmed, type: Boolean, synthetic: true },

    ## Recoverable
    { field: :rps, as: :reset_password_sent_at, type: Time, default: nil, internal: true },
    { field: :rpt, as: :reset_password_token, type: String, internal: true },

    ## Lockable (forces a password reset)
    { field: :fa, as: :failed_attempts, type: Integer, default: 0, internal: true },
    { field: :la, as: :locked_at, type: Time, default: nil, internal: true },

    { embeds_one:  :preference, store_as: :pr, autobuild: true  },

    # Stripe Customer identifier
    { field: :ci, as: :customer_id, type: String, internal: true },
    { field: :registered, type: Boolean, synthetic: true },

    # Subscriptions
    # Note:
    # - Use :detect, and not :find, when searching since :find conflicts with MongoDB methods
    { embeds_many: :subscriptions, store_as: :sb, outbound: true }
  ]

  locker locking_name_field: :lln, locked_at_field: :lla

  index({_id: 1, ln: 1}, { sparse: true, unique: true, expire_after_seconds: lock_timeout })

  index({fn: 1}, { collation: { locale: 'en', strength: 2 }, sparse: true })
  index({ln: 1}, { collation: { locale: 'en', strength: 2 }, sparse: true })
  index({em: 1}, { collation: { locale: 'en', strength: 2 }, sparse: true, unique: true })
  index({ph: 1}, sparse: true)
  index({ro: 1}, sparse: true)
  index({eca: 1}, sparse: true)
  index({pca: 1}, sparse: true)
  index({ci: 1}, sparse: true)

  index({'pr.av' => 1}, sparse: true)
  index({'pr.sv' => 1}, sparse: true)
  index({'pr.ae' => 1}, sparse: true)
  index({'pr.ap' => 1}, sparse: true)
  index({'pr.ss' => 1}, sparse: true)
  index({'pr.au' => 1}, sparse: true)
  index({'pr.ct' => 1}, sparse: true)
  index({'pr.db' => 1}, sparse: true)
  index({'pr.ri' => 1}, sparse: true)

  index({'sb.so' => 1}, sparse: true)
  index({'sb.ro' => 1}, sparse: true)
  index({'sb.xo' => 1}, sparse: true)
  index({'sb.st' => 1}, sparse: true)
  index({'sb.si' => 1}, sparse: true)
  index({'sb.pi' => 1}, sparse: true)
  index({'sb.rc' => 1}, sparse: true)
  index({'sb.cv' => 1}, sparse: true)
  index({'sb.vk' => 1}, sparse: true)

  PROTECTED_FIELDS = [
    :role.jsonize,
  ]

  # Note:
  # - These scopes only check the appropriate field
  # - Combine them to be more restrictive (e.g., self.has_recall_subscription.has_confirmed_email)

  scope :created_after, lambda{|t=Time.now.end_of_day| self.where(:created_at.gte => t)}
  scope :created_before, lambda{|t=Time.now.end_of_day| self.where(:created_at.lte => t)}
  scope :created_during, lambda{|st=Time.now.beginning_of_day, et=st.end_of_day| self.and([{created_at: { '$gte' => st}}, {created_at: { '$lte' => et}}])}
  scope :created_on, lambda{|t=Time.now.beginning_of_day| self.created_during(t)}

  scope :is_not_guest, lambda{self.ne(email: Constants::GUEST_EMAIL)}

  scope :in_creation_order, lambda{self.order_by(c_at: 1)}

  scope :in_roles, lambda{|*roles| self.is_not_guest.in(ro: roles)}
  Constants::ROLES.each do |role|
    self.scope "is_#{role}".to_sym, lambda{self.where(ro: role)}
  end

  {
    au: :audience,
    ct: :categories,
    db: :distribution,
    ri: :risk
  }.each do |field, name|
    field = "pr.#{field}"
    self.scope "includes_#{name}".to_sym, lambda{|values| self.in(field => Array(values))}
    self.scope "has_all_#{name}".to_sym, lambda{|values| self.all(field => Array(values))}
  end

  scope :has_confirmed_email, lambda{ self.lte(email_confirmed_at: Time.now)}
  scope :needs_email_confirmation, lambda{ self.where(email_confirmed_at: nil)}

  scope :has_confirmed_phone, lambda{ self.and([{:phone.nin => ['', nil]}, {phone_confirmed_at: {'$lte' => Time.now}}])}
  scope :needs_phone_confirmation, lambda{ self.and([{:phone.nin => ['', nil]}, {phone_confirmed_at: nil}])}

  scope :for_alert, lambda{ self.only([:first_name, :last_name, :email, :phone, 'preference.alert_by_email', 'preference.alert_by_phone'])}
  scope :for_users, lambda{|ids=[]| self.in(_id: ids)}

  scope :is_confirmed, lambda{|at=Time.now| self.and([
    {email_confirmed_at: {'$lte' => at}},
    '$or' => [
        {phone: nil},
        {phone_confirmed_at: {'$lte' => at}}
      ]
  ])}
  scope :needs_confirmation, lambda{ self.or([
    {email_confirmed_at: nil},
    {'$and' => [
      {:phone.nin => ['', nil]},
      {phone_confirmed_at: nil}]
  }])}

  scope :with_customer, lambda{|customer| self.where(customer_id: customer.is_a?(Stripe::Customer) ? customer.id : customer)}

  scope :with_subscription_expiring_after, lambda{|t=Time.now.end_of_day| self.where('sb.xo' => { '$gte' => t})}
  scope :with_subscription_expiring_before, lambda{|t=Time.now.end_of_day| self.where('sb.xo' => { '$lte' => t})}
  scope :with_subscription_expiring_during, lambda{|st=Time.now.beginning_of_day, et=st.end_of_day| self.where(sb: {
    '$elemMatch' => {
      '$and' => [
        {'xo' => { '$gte' => st}},
        {'xo' => { '$lte' => et}}
      ]
    }})
  }
  scope :with_subscription_expiring_on, lambda{|t=Time.now.beginning_of_day| self.with_subscription_expiring_during(t)}

  scope :with_subscription_status, lambda{|values| self.where('sb.st' => { '$in' => Array(values)})}
  scope :with_active_subscription, lambda{self.with_subscription_status(Subscription::ACTIVE_STATUS)}

  scope :has_active_subscription, lambda{self.where(sb: {
    '$elemMatch' => {
      'xo' => { '$gte' => Time.start_of_grace_period}
    }
  })}

  scope :has_recall_subscription, lambda{self.is_member.where(sb: {
    '$elemMatch' => {
      'xo' => { '$gte' => Time.start_of_grace_period},
      'rc' => true
    }
  })}

  scope :has_vehicle_subscription, lambda{self.is_member.where(sb: {
    '$elemMatch' => {
      'xo' => { '$gte' => Time.start_of_grace_period},
      'cv' => { '$gt' => 0 }
    }
  })}

  scope :owns_subscription, lambda{|s| self.where('sb._id' => s.is_a?(BSON::ObjectId) ? s : s.id)}

  scope :owns_vin, lambda{|v| self.where('sb.vn._id' => v.is_a?(BSON::ObjectId) ? v : v.id)}

  scope :is_inactive, lambda{self.is_member.is_not_guest.or([
    {'sb' => nil},
    {'sb' => { '$size' => 0}},
    {'sb' => { '$not' => {
      '$elemMatch' => {
        'xo' => {'$gte' => Time.start_of_grace_period}
      }
    }}}
  ])}

  scope :with_first_name, lambda{|first_name| self.where(first_name: first_name).collation({ locale: 'en', strength: 2 })}
  scope :with_last_name, lambda{|last_name| self.where(last_name: last_name).collation({ locale: 'en', strength: 2 })}
  scope :with_email, lambda{|email| self.where(email: email).collation({ locale: 'en', strength: 2 })}
  scope :with_phone, lambda{|phone| self.where(phone: phone)}

  # Note:
  # - These scopes combine and build on the above to answer restrictive queries

  scope :has_interest_in_recall, lambda{|recall|
    self.is_member.has_recall_subscription.and([
      {'pr.au' => {'$in' => recall.audience}},
      {'pr.ct' => {'$in' => recall.categories}},
      {'pr.db' => {'$in' => recall.distribution}},
      {'pr.ri' => {'$in' => Array(recall.risk)}}
    ])
  }

  scope :wants_recall_email_alert, lambda{|recall|
    self.is_member.has_confirmed_email.has_recall_subscription.and([
      {'pr.au' => {'$in' => recall.audience}},
      {'pr.ct' => {'$in' => recall.categories}},
      {'pr.db' => {'$in' => recall.distribution}},
      {'pr.ri' => {'$in' => Array(recall.risk)}},
      {'pr.ae' => true}
    ])
  }

  scope :wants_recall_summary, lambda{
    self.is_member.has_confirmed_email.has_recall_subscription.where('pr.ss' => true)
  }

  scope :has_interest_in_vkey, lambda{|vkey|
    self.is_member.where(sb: {
      '$elemMatch' => {
        'xo' => { '$gte' => Time.start_of_grace_period},
        'cv' => { '$gt' => 0 },
        'vk' => { '$in' => Array(vkey)}
      }
    })
  }

  scope :has_no_interest_in_vkey, lambda{|vkey|
    self.is_member.where(sb: {
      '$elemMatch' => {
        'xo' => { '$gte' => Time.start_of_grace_period},
        'cv' => { '$gt' => 0 },
        'vk' => { '$nin' => Array(vkey)}
      }
    })
  }

  scope :wants_vehicle_email_alert, lambda{|vkey|
    self.is_member.where(sb: {
      '$elemMatch' => {
        'xo' => { '$gte' => Time.start_of_grace_period},
        'cv' => { '$gt' => 0 },
        'vk' => { '$in' => Array(vkey)}
      }
    }).where('pr.av' => true)
  }

  scope :wants_vehicle_summary, lambda{
    self.is_member.has_confirmed_email.has_vehicle_subscription.where('pr.sv' => true)
  }

  scope :has_unreviewed_vin, lambda{
    self.is_member.where(sb: {
      '$elemMatch' => {
        'xo' => {'$gte' => Time.start_of_grace_period},
        'cv' => {'$gt' => 0},
        'vn' => {
          '$elemMatch' => {
            'vin' => {'$nin' => [nil, '']},
            'rv' => {'$in' => [nil, false]}
          }
        }
      }
    })
  }

  before_validation :ensure_preferences
  before_validation :ensure_role
  after_validation :synchronize_stripe

  before_save :reset_confirmations
  after_save :send_tokens

  validates_length_of :first_name, maximum: 50, allow_blank: true
  validates_length_of :last_name, maximum: 75, allow_blank: true

  validates_inclusion_of :role, in: Constants::ROLES

  has_secure_password(validations: false)

  validates_presence_of :password, unless:lambda{|u| u.persisted? || u.password_digest.present? }
  validates_length_of :password, maximum: ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED, allow_blank: true
  validates_password :password, unless:lambda{|u| u.errors.has_key?(:password)}, allow_blank: true

  validates_datetime :email_confirmed_at, on_or_before: :midnight, allow_blank: true
  validates_datetime :email_confirmation_sent_at, on_or_before: :midnight, allow_blank: true
  validates_numericality_of :email_errors, only_integer: true, greater_than_or_equal_to: 0

  validates_datetime :phone_confirmed_at, on_or_before: :midnight, allow_blank: true
  validates_datetime :phone_confirmation_sent_at, on_or_before: :midnight, allow_blank: true

  validates_presence_of :customer_id, if: lambda{|u| u.subscriptions.length > 0}

  class<<self

    def destroy_with_stripe(user)
      StripeHelper.delete_customer(user) rescue nil
      user.destroy
    end

    def from_access_token(token)
      user_id = JsonWebToken.decode(token)
      u = User.find(user_id)
      u.access_token == token ? u : nil
    rescue
      nil
    end

    def guest_user
      u = User.with_email(Constants::GUEST_EMAIL).first rescue nil
      if u.blank?
        begin
          u = User.create!({
                email: Constants::GUEST_EMAIL,
                first_name: Constants:: GUEST_FIRST_NAME,
                last_name: Constants::GUEST_LAST_NAME,
                role: 'member',
                password: Helper.generate_password,
              })
          preference = u.preference
          preference.alert_by_email =
          preference.alert_by_phone =
          preference.send_summaries =
          preference.alert_for_vins =
          preference.send_vin_summaries = false
          preference.audience =
          preference.categories =
          preference.distribution =
          preference.risk = nil
          u.save!
        rescue StandardError => e
          logger.error "Failed to create Guest User - #{e}"
        end
      end
      u
    end

    unless Rails.env.production?
      def dj
        count = 0
        User.or([{first_name: 'jim'}, {first_name: 'j'}]).collation({ locale: 'en', strength: 2 }).each do |u|
          puts "Destroying #{u.email}"
          User.destroy_with_stripe(u)
          count += 1
        end
        puts "Destroyed #{count} users"
      end

      def me
        User.with_email('brendandixon@me.com').first
      end
    end

    def normalize_email(email)
      email.is_a?(String) ? email.downcase.squish : email
    end

    def normalize_password(password)
      password.is_a?(String) ? password.squish : password
    end

  end

  def initialize(attributes = nil)
    super(attributes.is_a?(User) ? attributes.attributes : attributes)
  end

  def em=(v)
    self[:em] = User.normalize_email(v)
  end
  alias :email= :em=

  def password=(v)
    super(User.normalize_password(v))
    
    self.reset_password_sent_at =
    self.reset_password_token = nil if v.present?
  end

  def audience
    self.preference.audience
  end

  def categories
    self.preference.categories
  end

  def distribution
    self.preference.distribution
  end

  def risk
    self.preference.risk
  end

  Constants::ROLES.each do |role|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def is_#{role}?
        self.role == '#{role}'
      end
    METHODS
  end

  def is_guest?
    self.email == Constants::GUEST_EMAIL
  end

  def registered?
    self.customer_id.present?
  end
  alias :registered :registered?

  def acts_as_admin?
    self.is_admin?
  end

  def acts_as_worker?
    acts_as_admin? || self.is_worker?
  end

  def acts_as_member?
    acts_as_worker? || self.is_member?
  end

  %w(
    alert_by_email
    alert_by_phone
    send_summaries
    alert_for_vins
    send_vin_summaries
  ).each do |field|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def #{field}!(f = true)
        self.preference.#{field}!(f)
      end

      def #{field}?
        self.preference.#{field}?
      end
    METHODS
  end

  %w(email phone).each do |field|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def #{field}_confirmed?
        self.#{field} == nil || ((self.#{field}_confirmed_at || Constants::FAR_FUTURE) < Time.now)
      end
      alias :#{field}_confirmed :#{field}_confirmed?

      def #{field}_unconfirmed?
        !self.#{field}_confirmed?
      end
      alias :#{field}_unconfirmed :#{field}_unconfirmed?

      def needs_#{field}_confirmation?
        !self.#{field}_confirmed? && self.#{field}_confirmation_token.present? && self.#{field}_confirmation_sent_at.blank?
      end

      def send_#{field}_token!
        self.update_attribute(:#{field}_confirmation_sent_at, Time.now.utc.beginning_of_minute)
      end

      def is_#{field}_token?(token)
        self.#{field}_confirmation_token.present? && self.#{field}_confirmation_token == token
      end
    METHODS
  end

  def email_confirmed!
    self.update_attributes!({
      email_errors: 0,
      email_confirmed_at: Time.now.utc.beginning_of_minute,
      email_confirmation_sent_at: nil,
      email_confirmation_token: nil
    })
  end

  def email_unconfirmed!
    self.update_attributes!({
      email_errors: 0,
      email_confirmed_at: nil,
      email_confirmation_sent_at: nil,
      email_confirmation_token: Helper.generate_token
    })
  end

  def email_errored!
    attributes = {
      email_errors: self.email_errors + 1
    }

    if attributes[:email_errors] >= AragornConfig.allowed_email_errors
      attributes[:email_confirmed_at] =
      attributes[:email_confirmation_sent_at] =
      attributes[:email_confirmation_token] = nil
    end

    self.update_attributes!(attributes)
  end

  def email_succeeded!
    return unless self.email_errors > 0
    self.update_attributes(email_errors: 0)
  end

  def email_suspended?
    self.email_errors >= AragornConfig.allowed_email_errors
  end
  alias :email_suspended :email_suspended?

  def phone_confirmed!
    self.update_attributes!({
      phone_confirmation_token: nil,
      phone_confirmed_at: Time.now.utc.beginning_of_minute,
      phone_confirmation_sent_at: nil
    })
  end

  def phone_unconfirmed!
    self.update_attributes!({
      phone_confirmation_token: Helper.generate_token,
      phone_confirmed_at: nil,
      phone_confirmation_sent_at: nil
    })
  end

  def authentication_failed!
    self.lock_account!(self.failed_attempts + 1)
  end

  def lock_account!(attempts = Constants::MAXIMUM_AUTHENTICATION_FAILURES)
    self.update_attributes!({
      failed_attempts: attempts,
      locked_at: attempts >= Constants::MAXIMUM_AUTHENTICATION_FAILURES ? Time.now : nil
    })
  end

  def account_locked?
    (self.locked_at || Constants::NEVER) <= Time.now
  end

  def unlock_account!
    return unless account_locked?
    self.update_attributes!({
      failed_attempts: 0,
      locked_at: nil
    })
  end

  def needs_reset_token?
    self.reset_password_token.present? && self.reset_password_sent_at.blank?
  end

  def reset_password!
    self.password = Helper.generate_password
    self.update_attributes!({
      password_digest: self.password_digest,
      reset_password_sent_at: nil,
      reset_password_token: Helper.generate_token
    })
  end

  def send_reset_token!
    self.update_attribute(:reset_password_sent_at, Time.now.utc.beginning_of_minute)
  end

  def is_reset_token?(token)
    self.reset_password_token.present? && self.reset_password_token == token
  end

  def clear_access_token!
    self.update_attribute(:access_token, nil)
  end

  def ensure_access_token!(exp = Helper.generate_access_token_expiration)
    refresh_access_token! unless self.access_token.present? && JsonWebToken.valid?(self.access_token, self.id)
  end

  def refresh_access_token!(exp = Helper.generate_access_token_expiration)
    if self.persisted?
      self.update_attributes!({
        access_token: generate_token(exp),
        failed_attempts: 0,
        locked_at: nil
      })
    else
      self.update_attributes({
        access_token: generate_token(exp),
        failed_attempts: 0,
        locked_at: nil
      })
    end
  end

  def synchronize_stripe!(stripe_subscription)
    self.with_lock(reload: true) do
      subscription = self.subscription_from_stripe_id(stripe_subscription.id)

      if subscription.blank? && Subscription::INACTIVE_STATUS.include?(stripe_subscription.status)
        logger.warn("User #{self.email} is not subscribed to Stripe subscription #{stripe_subscription.id} with status #{stripe_subscription.status}")
        return
      end

      if subscription.present? && subscription.plan_id != stripe_subscription.plan.id
        logger.warn("Stripe subscription #{stripe_subscription.id} expects plan #{stripe_subscription.plan.id}, User #{self.email} has plan #{subscription.plan_id}")
        return
      end

      if subscription.blank?
        subscription = Subscription.build_from_stripe(stripe_subscription)
        self.subscriptions << subscription
      else
        subscription.synchronize_with_stripe(stripe_subscription)
      end

      self.save ? subscription : nil
    end
  rescue Mongoid::Locker::Errors::MongoidLockerError
    logger.error("Failed to aquire lock and synchronize Stripe subscription #{stripe_subscription.id} for User #{self.email}")
    nil
  end

  def active_plans(at_time=Time.now)
    return [] if self.subscriptions.blank?
    return self.active_subscriptions(at_time).map{|s| s.plan}.uniq.sort
  end

  def active_subscriptions(at_time=Time.now)
    self.subscriptions.filter{|s| s.active?(at_time)}
  end

  def recall_subscription(at_time=Time.now)
    self.active_subscriptions(at_time).detect{|s| s.recalls?}
  end

  def has_recall_subscription?(at_time=Time.now)
    return true if self.acts_as_worker? || self.is_guest?
    self.recall_subscription(at_time).present?
  end

  def vin_subscriptions(at_time=Time.now)
    self.active_subscriptions(at_time).filter{|s| s.vins?}
  end

  def has_vehicle_subscription?(at_time=Time.now)
    return true if self.acts_as_worker?
    self.vin_subscriptions(at_time).present?
  end

  def active?(at_time=Time.now)
    self.active_subscriptions(at_time).present?
  end

  def inactive?(at_time=Time.now)
    !self.active?(at_time)
  end

  def subscribed_to?(plan, at_time=Time.now)
    self.active_subscriptions(at_time).detect{|s| s.for_plan?(plan)}.present?
  end

  def can_subscribe_to?(plan)
    !plan.for_recalls? || !self.has_recall_subscription?
  end

  def subscriptions_for_plan(plan)
    self.active_subscriptions.filter{|s| s.for_plan?(plan)}
  end

  def subscription_from_id(id)
    self.subscriptions.detect{|s| s.id == id}
  end

  def subscription_from_stripe_id(id)
    self.subscriptions.detect{|s| s.for_stripe_id?(id)}
  end

  def unreviewed_vins
    self.vins.filter{|vin| !vin.reviewed? }
  end

  def vin_from_id(id)
    (self.subscriptions || []).each do |s|
      v = (s.vins || []).detect{|v| v.id == id}
      return v if v.present?
    end
    nil
  end

  def vins(all=false)
    self.subscriptions.map{|s| (all || s.active?) ? s.vins : []}.flatten
  end

  def as_json(*args, **options)
    return super(args, options) if options[:exclude_related]

    options.delete(:exclude_related)
    related = self.active_plans
    coupon = EmailCoupon.coupon_for_email(self.email)
    related << coupon if coupon.present?
    super(args, options.merge(related: related))
  end

  def <=>(other)
    return -1 unless other.is_a?(User)
    self.email <=> other.email
  end

  protected

    def ensure_id
      super
      self.preference.send(:ensure_id) if self.preference.present?
      (self.subscriptions || []).each{|s| s.send(:ensure_id)}
    end

    def ensure_preferences
      return if self.is_guest?
      return unless self.is_member?
      return unless self.has_recall_subscription?

      self.preference.audience = FeedConstants::DEFAULT_AUDIENCE if self.preference.audience.blank?
      self.preference.categories = FeedConstants::DEFAULT_CATEGORIES if self.preference.categories.blank?
      self.preference.distribution = USRegions::STATES if self.preference.distribution.blank?
      self.preference.risk = FeedConstants::DEFAULT_RISK if self.preference.risk.blank?
    end

    def ensure_role
      self.role = 'member' unless Constants::ROLES.include?(self.role)
    end

    def generate_token(exp = Helper.generate_access_token_expiration)
      JsonWebToken.encode(self.id, exp)
    end

    def reset_confirmations
      return if self.is_guest? || self.acts_as_worker?

      if self.email_changed? || self.email_suspended?
        self.email_confirmed_at =
        self.email_confirmation_sent_at = nil
      end

      if self.email_changed?
        self.email_confirmation_token = Helper.generate_token
      end

      if self.phone_changed?
        self.phone_confirmed_at =
        self.phone_confirmation_sent_at = nil
        self.phone_confirmation_token = Helper.generate_token
      end
    end

    def send_tokens
      return if self.is_guest? || self.acts_as_worker?
      SendEmailConfirmationJob.perform_later(self.id.to_s) if self.needs_email_confirmation?
      # TODO: Send Phone text confirmation
      SendPasswordResetTokenJob.perform_later(self.id.to_s) if self.needs_reset_token?
    end

    def synchronize_stripe
      return if self.new_record? || !self.errors.empty?
      return unless self.email_changed?
      return unless self.customer_id.present?
      StripeHelper.update_customer(self)
    end

end
