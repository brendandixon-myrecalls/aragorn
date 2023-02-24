class Recall
  include ActiveModel::Callbacks
  include ActionView::Helpers
  include Authority::Abilities
  include Mongoid::Document
  include Mongoid::Timestamps::Short
  include Fields
  include Validations

  ID_PATTERN = /[A-Fa-f0-9]{64,64}/
  
  REQUIRED = [:audience, :categories, :distribution, :risk]
  STATES = ['unreviewed', 'reviewed', 'sent']
  
  define_fields [
    { field: :_id, as: :id, type: String },

    { field: :fn, as: :feed_name, type: String },
    { field: :fs, as: :feed_source, type: String },
    { field: :t, as: :title, type: String },
    { field: :d, as: :description, type: String },
    { field: :l, as: :link, type: String },
    { field: :pd, as: :publication_date, type: Time },
    { field: :st, as: :state, type: String, default: STATES.first },
    { field: :af, as: :affected, type: Array },
    { field: :al, as: :allergens, type: Array },
    { field: :au, as: :audience, type: Array },
    { field: :ct, as: :categories, type: Array },
    { field: :co, as: :contaminants, type: Array },
    { field: :db, as: :distribution, type: Array },
    { field: :ri, as: :risk, type: String }
  ]

  index({fn: 1}, sparse: true)
  index({fs: 1}, sparse: true)
  index({pd: 1}, sparse: true)
  index({st: 1}, sparse: true)
  index({af: 1}, sparse: true)
  index({al: 1}, sparse: true)
  index({au: 1}, sparse: true)
  index({ct: 1}, sparse: true)
  index({co: 1}, sparse: true)
  index({db: 1}, sparse: true) 
  index({ri: 1}, sparse: true)

  after_create :create_token
  after_destroy :destroy_token

  before_validation :ensure_state

  validates_recall_id :id, allow_blank: false

  validates_inclusion_of :feed_name, in: FeedConstants::NAMES, allow_blank: false
  validates_inclusion_of :feed_source, in: FeedConstants::SOURCES, allow_blank: false

  validates_length_of :title, minimum: 3, allow_blank: false

  validates_is_uri :link, allow_blank: false

  validates_datetime :publication_date, on_or_before: :midnight, allow_blank: false

  validates_inclusion_of :state, in: STATES, allow_blank: false

  validates_intersection_of :affected, in: FeedConstants::AFFECTED, allow_blank: true
  validates_intersection_of :allergens, in: FeedConstants::FOOD_ALLERGENS, allow_blank: true
  validates_intersection_of :audience, in: FeedConstants::AUDIENCE, allow_blank: true
  validates_intersection_of :categories, in: lambda{|r| Recall.categories_for(r.feed_name)}, allow_blank: true, if: lambda{ self.feed_name.present? }
  validates_intersection_of :contaminants, in: FeedConstants::ALL_CONTAMINANTS, allow_blank: true
  validates_intersection_of :distribution, in: USRegions::ALL_STATES, allow_blank: true
  validates_inclusion_of :risk, in: FeedConstants::RISK, allow_blank: true

  validate :validate_allergens
  validate :validate_categories
  validate :validate_required

  scope :from_feeds, lambda{|values| self.in(fn: Array(values))}
  scope :from_feed, lambda{|fn| self.where(fn: fn)}
  scope :from_source, lambda{|fs| self.where(fs: fs)}

  scope :has_id, lambda{|ids| self.in(id: Array(ids))}

  scope :in_published_order, lambda{|asc=false| self.order_by(publication_date: asc ? 1 : -1)}

  scope :in_state, lambda{|states| self.in(state: Array(states))}
  scope :needs_review, lambda{ self.in_state('unreviewed')}
  scope :needs_sending, lambda{ self.in_state('reviewed')}
  scope :was_sent, lambda{ self.in_state('sent')}

  scope :published_after, lambda{|t=Time.now.end_of_day| self.where(:publication_date.gte => t)}
  scope :published_before, lambda{|t=Time.now.end_of_day| self.where(:publication_date.lte => t)}
  scope :published_during, lambda{|st=Time.now.beginning_of_day, et=st.end_of_day| self.and([{publication_date: { '$gte' => st}}, {publication_date: { '$lte' => et}}])}
  scope :published_on, lambda{|t=Time.now.beginning_of_day| self.published_during(t)}

  [:affected, :allergens, :audience, :categories, :contaminants, :distribution, :names, :risk, :sources].each do |field|
    search_field = case field
                  when :names then :feed_name
                  when :sources then :feed_source
                  else field
                  end
    values = Array(values)

    self.scope "includes_#{field}".to_sym, lambda{|values| self.in("#{search_field}" => values)}
    self.scope "excludes_#{field}".to_sym, lambda{|values| self.nin("#{search_field}" => values)}

    unless [:names, :risk, :sources].include?(field)
      self.scope "has_all_#{field}".to_sym, lambda{|values| self.all("#{search_field}" => values)}
    end
  end

  class<<self
    
    def categories_for(name)
      FeedConstants::NAME_CATEGORIES[name] || []
    end

    def compare_recall_states(this_state, that_state)
      return 0 if this_state == that_state
      return -1 if this_state == 'unreviewed' && that_state != 'unreviewed'
      return -1 if this_state == 'reviewed' && that_state == 'sent'
      return 1
    end

    def from_path(path)
      Recall.from_json(File.read(path))
    end

    def generate_id(s)
      Digest::SHA256.digest(s || '').unpack('H*').first
    end

    unless Rails.env.production?
      def random_id
        self.generate_id(Helper.generate_token)
      end
    end

  end

  def attributes_to_json(**options)
    h = super(**options)
    h[:token] = self.token if self.token.present?
    h
  end

  def t=(v)
    self[:t] = strip_tags(v || '').squish
  end
  alias :title= :t=

  def d=(v)
    self[:d] = strip_tags(v || '').squish
  end
  alias :description= :d=

  def l=(v)
    self[:l] = v
    ensure_id
  end
  alias :link= :l=

  def pd=(v)
    v = v.to_time if v.is_a?(Date) || v.is_a?(DateTime)
    self[:pd] = v.is_a?(Time) ? v.utc.beginning_of_minute : v
  end
  alias :publication_date= :pd=

  def acts_as_contaminable?
    FeedConstants.acts_as_contaminable?(self.categories)
  end

  def can_have_allergens?
    FeedConstants.can_have_allergens?(self.categories)
  end

  def acts_as_vehicle?
    FeedConstants.acts_as_vehicle?(self.categories)
  end

  def canonical_id
    self._id.to_s
  end

  def canonical_name
    "#{self.publication_date.to_s(:file_name)}-#{self.feed_name}-#{self.canonical_id}"
  end

  def for_audience?(audiences)
    audiences = [audiences] unless audiences.is_a?(Array)
    ((self.audience || []) & audiences).length == audiences.length
  end

  FeedConstants::AUDIENCE.each do |audience|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def for_#{audience}?
        self.for_audience?('#{audience}')
      end
    METHODS
  end

  def high_risk?
    self.risk == 'probable'
  end

  def sanitize!
    self.title = self.title
    self.description = self.description
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

  def should_send_email?
    FeedConstants::EMAILED_RISK.include?(self.risk)
  end

  def should_send_phone?
    FeedConstants::TEXTED_RISK.include?(self.risk)
  end

  def share_token
    @share_token ||= ShareToken.for_recall(self).first rescue nil
  end

  def token
    self.share_token.present? ? self.share_token.token : nil
  end

  def to_s
    self.id.to_s
  end

  def hash
    self._id.to_s
  end

  def eql?(other)
    return false unless other.is_a?(Recall)
    self.hash === other.hash
  end
  alias :equal? :eql?
  alias :== :eql?

  def <=>(other)
    return -1 unless other.is_a?(Recall)
    return self.publication_date <=> other.publication_date unless self.publication_date == other.publication_date
    self.canonical_id <=> other.canonical_id
  end

  protected

    def create_token
      @share_token = ShareToken.create(self)
    rescue StandardError => e
      logger.error "Failed to create token for Recall #{self.id} -- #{e}"
    end

    def destroy_token
      self.share_token.destroy if self.share_token.present?
    end

    def ensure_id
      self.id = Recall.generate_id(self.l)
    end

    def ensure_state
      self.state = STATES.first if self.state.blank?
    end

    def validate_allergens
      return unless self.feed_name.present?
      return if self.allergens.blank? || self.can_have_allergens?
      self.errors.add(:categories, "#{self.categories.join(', ')} cannot have allergens")
    end

    def validate_categories
      return unless self.feed_name.present?
      return if self.contaminants.blank? || self.acts_as_contaminable?
      self.errors.add(:categories, "#{self.categories.join(', ')} cannot have contaminations")
    end

    def validate_required
      return if self.unreviewed?
      REQUIRED.each do |field|
        self.errors.add(field, "is required") if self[field].blank?
      end
    end

end
