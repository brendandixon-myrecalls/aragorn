class VehicleRecall
  include ActiveModel::Callbacks
  include ActionView::Helpers
  include Authority::Abilities
  include Mongoid::Document
  include Mongoid::Timestamps::Short
  include Fields
  include Validations
  include Vehicles

  STATES = ['reviewed', 'sent']

  define_fields [
    { field: :_id, as: :id, type: BSON::ObjectId },

    { field: :ci, as: :campaign_id, type: String },
    
    { field: :pd, as: :publication_date, type: Time },
    { field: :cp, as: :component,        type: String },
    { field: :s,  as: :summary,          type: String },
    { field: :c,  as: :consequence,      type: String },
    { field: :r,  as: :remedy,           type: String },

    { field: :vk, as: :vkeys,    type: Array, internal: true },

    { field: :st, as: :state, type: String, default: STATES.first },

    { embeds_many: :vehicles, store_as: :vh }
  ]

  index({ci: 1}, {sparse: true, unique: true})
  index({pd: 1}, sparse: true)
  index({vh: 1}, sparse: true)
  index({st: 1}, sparse: true)

  before_validation :ensure_state
  before_validation :ensure_vehicles
  before_validation :ensure_vkeys
  
  before_save :normalize

  validates_length_of :campaign_id, is: Vehicles::CAMPAIGN_IDENTIFIER_LENGTH
  validates_uniqueness_of :campaign_id

  validates_datetime :publication_date, on_or_before: :midnight, allow_blank: false
  validates_presence_of :component
  validates_presence_of :summary
  validates_presence_of :consequence
  validates_presence_of :remedy

  validate :validate_vkeys

  validates_inclusion_of :state, in: STATES, allow_blank: false

  scope :has_id, lambda{|ids| self.in(id: Array(ids))}

  scope :for_campaign, lambda{|campaign_id| self.where(campaign_id: campaign_id)}
  scope :for_campaigns, lambda{|campaign_ids| self.in(campaign_id: Array(campaign_ids))}

  scope :in_published_order, lambda{|asc=false| self.order_by(publication_date: asc ? 1 : -1)}

  scope :published_after, lambda{|t=Time.now.end_of_day| self.where(:publication_date.gte => t)}
  scope :published_before, lambda{|t=Time.now.end_of_day| self.where(:publication_date.lte => t)}
  scope :published_during, lambda{|st=Time.now.beginning_of_day, et=st.end_of_day| self.and([{publication_date: { '$gte' => st}}, {publication_date: { '$lte' => et}}])}
  scope :published_on, lambda{|t=Time.now.beginning_of_day| self.published_during(t)}

  scope :for_vkeys, lambda{|vkeys| self.in(vkeys: Array(vkeys))}

  scope :in_state, lambda{|states| self.in(state: Array(states))}
  scope :needs_sending, lambda{ self.in_state('reviewed')}
  scope :was_sent, lambda{ self.in_state('sent')}

  class<<self

    def compare_recall_states(this_state, that_state)
      return 0 if this_state == that_state
      return -1 if this_state == 'reviewed' && that_state == 'sent'
      return 1
    end

    def ensure_vin_recalls(vin)
      vehicle = Vehicles::Basic.vehicle_from_vin(vin)
      Vehicles::Basic.vehicle_campaigns(vehicle).map do |campaign_id|
        if VehicleRecall.for_campaigns(campaign_id).exists?
          nil
        else
          vr = VehicleRecall.from_campaign(campaign_id)
          if vr.save && AwsHelper.upload_recall(vr)
            vr
          else
            vr.destroy rescue nil if vr.present?
            logger.warn "Unable to save VehicleRecall for Campaign #{campaign_id}"
            nil
          end
        end
      end.compact
    end

    def from_campaign(campaign_id)
      campaign = Vehicles::Basic.campaign_from_id(campaign_id)

      recall = VehicleRecall.new
      recall.campaign_id = campaign[:campaign_id] || campaign_id
      recall.publication_date = campaign[:publication_date]
      recall.vehicles = []
      recall.vkeys = []

      if campaign[:vehicles].blank?
        recall.component =
        recall.summary =
        recall.consequence =
        recall.remedy = "NHTSA Campaign #{campaign_id} is no longer valid"
      else
        recall.component = campaign[:component]
        recall.summary = campaign[:summary]
        recall.consequence = campaign[:consequence]
        recall.remedy = campaign[:remedy]
        recall.vehicles = campaign[:vehicles]
      end

      recall
    end

    def page_uri(campaign_id)
      URI::parse("https://www.nhtsa.gov/recalls?nhtsaId=#{campaign_id}")
    end

  end

  def pd=(v)
    v = v.to_time if v.is_a?(Date) || v.is_a?(DateTime)
    self[:pd] = v.is_a?(Time) ? v.utc.beginning_of_minute : v
  end
  alias :publication_date= :pd=

  def s=(v)
    self[:s] = self.cleanse_text(v)
  end
  alias :summary= :s=

  def c=(v)
    self[:c] = self.cleanse_text(v)
  end
  alias :consequence= :c=

  def r=(v)
    self[:r] = self.cleanse_text(v)
  end
  alias :remedy= :r=

  def acts_as_contaminable?
    false
  end

  def can_have_allergens?
    false
  end

  def acts_as_vehicle?
    true
  end

  def canonical_id
    self._id.to_s
  end

  def canonical_name
    "#{self.publication_date.to_s(:file_name)}-vehicles-#{self.canonical_id}"
  end

  def for_audience?(audiences)
    false
  end

  FeedConstants::AUDIENCE.each do |audience|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def for_#{audience}?
        false
      end
    METHODS
  end

  def high_risk?
    false
  end

  def sanitize!
    self.summary = self.summary
    self.consequence = self.consequence
    self.remedy = self.remedy
    self.save!
  end

  STATES.each do |state|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def #{state}?
        self.state == '#{state}'
      end

      def #{state}!
        self.state = '#{state}'
        self.save! unless self.new_record?
      end
    METHODS
  end

  def needs_sending?
    self.reviewed?
  end

  def to_s
    self.id.to_s
  end

  def <=>(other)
    return -1 unless other.is_a?(VehicleRecall)
    return self.publication_date <=> other.publication_date unless self.publication_date == other.publication_date
    self.campaign_id <=> other.campaign_id
  end

  protected

    def cleanse_text(t)
      strip_tags(t || '').squish
    end

    def ensure_id
      super
      (self.vehicles || []).each{|v| v.send(:ensure_id)}
    end

    def ensure_state
      self.state = STATES.first if self.state.blank?
    end

    def ensure_vehicles
      # Purge duplicates
      self.vehicles = (self.vehicles || []).uniq
    end

    def ensure_vkeys
      vkeys = self.vehicles.map{|v| v.to_vkey}.compact
      return if self.vkeys == vkeys
      self.vkeys = vkeys
    end

    def normalize
      self.component = self.component.titleize if self.component.is_a?(String)
    end

    def validate_vkeys
      if self.vkeys.any?{|vkey| !Vehicles.valid_vkey?(vkey)}
        self.errors.add(:vkeys, 'contains one or more invalid keys')
      elsif (self.vkeys || []).length != (self.vehicles || []).length
        self.errors.add(:vkeys, 'must contain all vehicles')
      elsif self.vehicles.present?
        return if (self.vehicles.map{|v| v.to_vkey} & self.vkeys).length == self.vkeys.length
        self.errors.add(:vkeys, 'must match vehicles')
      end
    end

end
