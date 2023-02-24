class SubscriptionsController < ApplicationController

  authorize_actions_for Subscription, only: COLLECTION_ACTIONS
  authority_actions cancel: :update

  before_action :ensure_ready
  before_action :set_subscription, except: COLLECTION_ACTIONS
  before_action :ensure_subscription, except: COLLECTION_ACTIONS
  before_action :ensure_authorized, except: COLLECTION_ACTIONS

  # GET /users/:user_id/subscriptions
  def index
    params = search_params

    @subscriptions = (user.subscriptions || []).sort
    @subscriptions = @subscriptions.select{|s| s.active?} unless params[:all]

    params = params.to_h.deep_symbolize_keys
    render json: Subscription.as_json_collection(@subscriptions, **params), status: :ok
  end

  # PUT/PATCH /users/:user_id/subscriptions/:id/cancel
  def cancel
    @subscription = StripeHelper.cancel_subscription(user, @subscription.stripe_id)
    render json: @subscription, status: :ok
  end

  # POST /users/:user_id/subscriptions
  def create
    @subscription = StripeHelper.create_subscription(
                    user,
                    plan,
                    EmailCoupon.coupon_for_email(user.email),
                    params[:token])

    render json: @subscription, status: :created
  end

  # GET /users/:user_id/subscriptions/:id
  def show
    render json: @subscription, status: :ok
  end

  protected

    def ensure_authorized
      unless current_user.acts_as_worker? || user == current_user
        raise Authority::SecurityViolation.new(current_user, self.action_name, @subscription)
      end
      authorize_action_for @subscription
    end

    def ensure_ready
      @plan =
      @subscription_id =
      @subscription_params =
      @subscription =
      @user = nil
    end

    def ensure_subscription
      return if @subscription.present?
      if action_name == 'create'
        @subscription = Subscription.new
      else
        raise Mongoid::Errors::DocumentNotFound.new(Subscription, params)
      end
    end

    def plan
      @plan ||= begin
        p = Plan.from_id(params[:plan])
        raise BadRequestError.new("#{params[:plan]} is not a known subscription plan") unless p.present?
        p
      end
    end

    def search_params
      @search_params ||= begin

        params[:all] = (params[:all] =~ Constants::TRUE_PATTERN).present? if params.has_key?(:all)

        params.permit(
          :all
        )
      end
    end

    def set_subscription
      @subscription ||= if subscription_id.present?
          user.subscription_from_id(subscription_id)
        else
          Subscription.from_json(subscription_params)
        end
    end

    def subscription_id
      @subscription_id ||= begin
        id = Subscription.json_params_for(params)[:id]
        BSON::ObjectId.from_string(id) if id.present?
      end
    end
 
    def subscription_params
      @subscription_params ||= Subscription.json_params_for(params)
    end

    def user
      @user ||= begin
        u = User.with_email(params[:email]).first rescue nil if (params[:email] =~ Constants::EMAIL_PATTERN).present?
        u = User.find(params[:user_id]) rescue nil if u.blank? && params[:user_id].present?
        u || current_user
      end
    end

end
