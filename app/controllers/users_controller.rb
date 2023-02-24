class UsersController < ApplicationController

  COLLECTION_ACTIONS = COLLECTION_ACTIONS + %w(status)

  authorize_actions_for User, only: COLLECTION_ACTIONS
  authority_actions status: :update

  skip_before_action :authenticate_user!, only: [:create]

  before_action :ensure_ready
  before_action :set_user, except: COLLECTION_ACTIONS
  before_action :ensure_user, except: COLLECTION_ACTIONS
  before_action :ensure_authorized

  after_action :send_new_users, only: [:create]

  SORT_TYPES = ['created', 'email']
  SUBSCRIPTION_TYPES = ['recalls', 'vehicles']
  SUMMARY_TYPES = ['recalls', 'vehicles']

  # GET /users
  def index
    params = search_params

    # TODO: Consider plucking and returning just email for Alerter and increasing the page size

    @users = User.is_not_guest.is_member
    @users = params[:sort] == 'created' ? @users.in_creation_order : @users.in_email_order

    @users = @users.created_after(params[:after]) if params[:after].present?
    @users = @users.created_before(params[:before]) if params[:before].present?

    if params[:summary] == 'recalls'
      @users = @users.wants_recall_summary

    elsif params[:summary] == 'vehicles'
      @users = @users.wants_vehicle_summary

    elsif params[:recall].present?
      recall = Recall.find(params[:recall]) rescue nil
      raise BadRequestError.new('Unknown recall') if recall.blank?

      if params[:alert]
        @users = @users.wants_recall_email_alert(recall)
      else
        @users = @users.has_interest_in_recall(recall)
      end

    elsif params[:vehicle].present?
      recall = VehicleRecall.find(params[:vehicle]) rescue nil
      raise BadRequestError.new('Unknown vehicle recall') if recall.blank?

      if params[:alert]
        @users = @users.wants_vehicle_email_alert(recall.vkeys)
      else
        @users = @users.has_interest_in_vkey(recall.vkeys)
      end

    elsif params[:vkeys].present?
      @users = @users.has_interest_in_vkey(params[:vkeys])

    elsif params[:subscription] == 'recalls'
      @users = @users.has_recall_subscription

    elsif params[:subscription] == 'vehicles'
      @users = @users.has_vehicle_subscription
    end

    @users = @users.limit(params[:limit]) if params[:limit].present?
    @users = @users.offset(params[:offset]) if params[:offset].present?

    params = params.to_h.deep_symbolize_keys
    render json: User.as_json_collection(@users, **params), status: :ok
  end

  # POST /users
  def create
    params = recaptcha_params
    if verify_recaptcha(model: @user, response: params[:recaptcha]) && @user.save
      render json: @user, status: :created
    else
      render_resource_errors(@user.merged_errors)
    end
  rescue
    raise Authentication::AuthenticationError.new
  end

  # GET /users/:id
  def show
    render json: @user, status: :ok
  end

  # PATCH/PUT /users/:id
  def update
    if @user.update_attributes(user_attributes)
      render json: @user, status: :ok
    else
      render_resource_errors(@user.merged_errors)
    end
  end

  # DELETE /users/:id
  def destroy
    User.destroy_with_stripe(@user)
    head :ok
  end

  # PATCH/PUT /users/status
  def status
    params = status_params
    raise BadRequestError.new('No users were supplied') if params[:users].blank?

    @users = User.find(params[:users])

    @users.each{|u| u.email_errored!} if params[:emailError]
    @users.each{|u| u.email_succeeded!} if params[:emailSuccess]

    head :ok
  end

  protected

    def ensure_authorized
      return if is_collection_action?
      authorize_action_for @user unless self.action_name == 'create'
    end

    def ensure_ready
      @user_attributes =
      @user_id =
      @user_params =
      @recaptcha_params =
      @search_params = nil
    end

    def ensure_user
      raise Mongoid::Errors::DocumentNotFound.new(User, params) unless @user.present?
    end

    def search_params
      @search_params ||= begin
        ensure_collection_params

        params[:sort] = 'email' unless SORT_TYPES.include?(params[:sort])

        # Return Users with 
        params[:subscription] = nil unless SUBSCRIPTION_TYPES.include?(params[:subscription])

        # Return User desiring Recall or VehicleRecall summary mail
        params[:summary] = nil unless SUMMARY_TYPES.include?(params[:summary])

        # Return Users interested in a Recall or VehicleRecall, possibly desiring an alert email
        params[:alert] = (params[:alert] =~ Constants::TRUE_PATTERN).present? if params.has_key?(:alert)
        params[:recall] = nil unless params[:recall].present? && params[:recall] =~ Recall::ID_PATTERN
        params[:vehicle] = nil unless params[:vehicle].present? && params[:vehicle] =~ Constants::BSON_ID_PATTERN

        # Return Users interested in a set of vkeys
        params[:vkeys] = Array(params[:vkeys]).map{|v| v =~ Vehicles::VKEY_REGEX ? v : nil}.compact if params[:vkeys].present?

        params.permit(
          :after,
          :before,
          :limit,
          :offset,
          :alert,
          :recall,
          :sort,
          :subscription,
          :summary,
          :vehicle,

          vkeys: []
        )
      end
    end

    def send_new_users
      SendNewUsersJob.perform_later if self.action_succeeded?
    end

    def set_user
      @user = if user_id.present?
        User.find(user_id) rescue nil
      else
        User.from_json(user_params)
      end
    end

    def status_params
      @status_params ||= begin

        params[:emailError] = (params[:emailError] =~ Constants::TRUE_PATTERN).present? if params.has_key?(:emailError)
        params[:emailSuccess] = (params[:emailSuccess] =~ Constants::TRUE_PATTERN).present? if params.has_key?(:emailSuccess)
        params[:users] = params[:users].split(',').map{|id| id =~ Constants::BSON_ID_PATTERN ? id : nil}.compact if params[:users].present?

        params.permit(
          :emailError,
          :emailSuccess,

          users: []
        )
      end
    end

    def user_attributes
      @user_attributes ||= User.attributes_from_params(user_params)
    end

    def user_id
      @user_id ||= begin
        params[:id] = nil unless params[:id].present? && params[:id] =~ Constants::BSON_ID_PATTERN
        id = user_params[:id]
        id.present? ? BSON::ObjectId.from_string(id) : nil
      end
    end

    def user_params
      @user_params ||= begin
        disallowed_attributes = current_user.present? && current_user.acts_as_worker? ? [] : User::PROTECTED_FIELDS
        User.json_params_for(params, disallowed_attributes)
      end
    end

end
