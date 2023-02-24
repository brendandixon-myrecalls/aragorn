class Preference
  include ActiveModel::Callbacks
  include Authority::Abilities
  include Mongoid::Document
  include Fields
  include Validations

  self.authorizer_name = 'UserAuthorizer'

  define_path singleton: true

  define_fields [
    { field: :_id, as: :id, type: BSON::ObjectId },

    # VIN Preferences
    { field: :av, as: :alert_for_vins, type: Boolean, default: true },
    { field: :sv, as: :send_vin_summaries, type: Boolean, default: true },

    # Recall Preferences
    { field: :ae, as: :alert_by_email, type: Boolean, default: true },
    { field: :ap, as: :alert_by_phone, type: Boolean, default: true },
    { field: :ss, as: :send_summaries, type: Boolean, default: true },

    { field: :au, as: :audience, type: Array },
    { field: :ct, as: :categories, type: Array },
    { field: :db, as: :distribution, type: Array },
    { field: :ri, as: :risk, type: Array },
  ]

  embedded_in :user

  # Note:
  # - Validation is not required of boolean fields since Mongoid forces their values to a boolean

  validates_intersection_of :audience, in: FeedConstants::AUDIENCE, allow_blank: true
  validates_intersection_of :categories, in: FeedConstants::PUBLIC_CATEGORIES, allow_blank: true
  validates_intersection_of :distribution, in: USRegions::ALL_STATES, allow_blank: true
  validates_intersection_of :risk, in: FeedConstants::RISK, allow_blank: true

  %w(
    alert_by_email
    alert_by_phone
    send_summaries
    alert_for_vins
    send_vin_summaries
  ).each do |field|
    class_eval <<-METHODS, __FILE__, __LINE__+1
      def #{field}!(f = true)
        self.#{field} = f
      end

      def #{field}?
        self.#{field}
      end
    METHODS
  end

end
