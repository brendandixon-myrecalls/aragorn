class ShareToken
  include ActiveModel::Callbacks
  include Mongoid::Document
  include Fields
  include Validations

  define_path path: :tokens

  define_fields [
    { field: :_id, as: :id, type: BSON::ObjectId },

    { field: :rid, as: :recall_id, type: String },
    { field: :ac, as: :access_count, type: Integer, default: 0 }
  ]

  index({rid: 1}, {sparse: true, unique: true})

  validates_recall_id :recall_id, allow_blank: false
  validates_uniqueness_of :recall_id
  validate :recall_exists

  validates_numericality_of :access_count, greater_then_or_equal_to: 0

  scope :for_recall, lambda{|r| self.where(recall_id: r.is_a?(Recall) ? r.id : r)}

  def initialize(attributes = nil)
    attributes = attributes.id if attributes.is_a?(Recall)
    attributes = {rid: attributes} if attributes.is_a?(String)
    super(attributes)
  end

  def rid=(v)
    @recall = nil
    self[:rid] = v.is_a?(Recall) ? v.id : v
  end
  alias :recall_id= :rid=

  def recall
    @recall ||= Recall.find(self.recall_id) rescue nil
  end

  def accessed!
    self.update_attribute(:access_count, self.access_count+1)
  end

  def token
    self.id.to_s
  end

  protected

    def recall_exists
      return if self.recall.present?
      self.errors.add(:recall_id)
    end

end
