class VinsController < ApplicationController

  COLLECTION_ACTIONS = COLLECTION_ACTIONS + %w(unreviewed)

  authorize_actions_for Subscription, only: COLLECTION_ACTIONS - %w(unreviewed)

  before_action :ensure_ready
  before_action :set_vin, except: COLLECTION_ACTIONS
  before_action :ensure_vin, except: COLLECTION_ACTIONS
  before_action :ensure_authorized, except: COLLECTION_ACTIONS + %w(reviewed)

  after_action :review_vins, only: [:update]

  # GET /users/:user_id/vins
  def index
    params = search_params

    @vins = (user.vins(params[:all]) || []).sort
    params[:related] = VehicleRecall.for_vkeys(@vins.map{|v| v.to_vkey}.uniq) if params[:recalls]

    params = params.to_h.deep_symbolize_keys
    render json: Vin.as_json_collection(@vins, **params), status: :ok
  end

  # PATCH/PUT /vins/:id/reviewed
  def reviewed
    ensure_authorized_worker(@vin)
    @vin.reviewed = true
    if @user.save
      head :ok
    else
      render_resource_errors(@vin.merged_errors)
    end
  end

  # GET /users/:user_id/vins/:id
  def show
    recalls = @vin.recalls if show_params[:recalls]
    render json: @vin.as_json(related: recalls), status: :ok
  end

  # GET /vins/unreviewed
  def unreviewed
    ensure_authorized_worker(Vin)
    vins = User.has_unreviewed_vin.map{|u| u.unreviewed_vins}.flatten
    render json: Vin.as_json_collection(vins), status: :ok
  end

  # PATCH/PUT /users/:user_id/vins/:id
  # Note:
  # - VINs are marked reviewed if another user has a VIN with the same vkey
  #   This way, only the first user with a specific vkey drives retrieval of the recalls
  def update
    @vin.attributes = vin_attributes
    if @vin.vin_changed? && !@vin.allow_updates?
      @vin.errors.add(:base, "VINs may be updated only once every #{Vin::MINIMUM_UPDATE_MONTHS} #{'month'.pluralize(Vin::MINIMUM_UPDATE_MONTHS)}")
      render_resource_errors(@vin.merged_errors)
    else
      @vin.updated_at = @vin.vin.present? ? Time.now.beginning_of_day.utc : Constants::DISTANT_PAST if @vin.vin_changed?
      @vin.reviewed = User.has_interest_in_vkey(@vin.to_vkey).exists?
      if @user.save
        recalls = @vin.recalls if show_params[:recalls]
        render json: @vin.as_json(related: recalls), status: :ok
      else
        render_resource_errors(@vin.merged_errors)
      end
    end
  end

  protected

    def ensure_authorized
      unless current_user.acts_as_worker? || user == current_user
        raise Authority::SecurityViolation.new(current_user, self.action_name, @vin)
      end
      authorize_action_for @vin
    end

    def ensure_authorized_worker(resource)
      raise Authority::SecurityViolation.new(current_user, self.action_name, resource) unless current_user.acts_as_worker?
    end

    def ensure_ready
      @vin_attributes =
      @vin_id =
      @vin_params =
      @vin =
      @search_params =
      @subscription =
      @user = nil
    end


    def ensure_vin
      raise Mongoid::Errors::DocumentNotFound.new(Vin, params) unless @vin.present?
    end

    def is_find_user_action?
      %(reviewed).include?(self.action_name)
    end

    def search_params
      @search_params ||= begin

        params[:all] = (params[:all] =~ Constants::TRUE_PATTERN).present? if params.has_key?(:all)
        params[:recalls] = (params[:recalls] =~ Constants::TRUE_PATTERN).present? if params.has_key?(:recalls)

        params.permit(
          :all,
          :recalls
        )
      end
    end

    def set_vin
      @vin ||= if vin_id.present?
          user.vin_from_id(vin_id)
        else
          Vin.from_json(vin_params)
        end
    end

    def review_vins
      return unless self.action_succeeded?
      return unless User.has_unreviewed_vin.exists?
      SendAlertsJob.perform_later("review_vins")

    rescue StandardError => e
      logger.error("Failed to initiate VIN review for Vin #{@vin.id}")
    end

    def show_params
      @show_params ||= begin
        params[:recalls] = (params[:recalls] =~ Constants::TRUE_PATTERN).present? if params.has_key?(:recalls)
        params.permit(
          :recalls
        )
      end
    end

    def vin_attributes
      @vin_attributes ||= Vin.attributes_from_params(vin_params)
    end

    def vin_id
      @vin_id ||= begin
        id = Vin.json_params_for(params)[:id]
        BSON::ObjectId.from_string(id) if id.present?
      end
    end
 
    def vin_params
      @vin_params ||= Vin.json_params_for(params)
    end

    def user
      @user ||= begin
        u = User.with_email(params[:email]).first rescue nil if (params[:email] =~ Constants::EMAIL_PATTERN).present?
        u = User.find(params[:user_id]) rescue nil if u.blank? && params[:user_id].present?
        u = User.owns_vin(vin_id).first rescue nil if u.blank? && vin_id.present? && self.is_find_user_action?
        u || current_user
      end
    end

end
