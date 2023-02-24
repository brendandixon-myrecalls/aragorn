class PreferencesController < ApplicationController

  before_action :ensure_ready
  before_action :set_preference, except: COLLECTION_ACTIONS
  before_action :ensure_preference, except: COLLECTION_ACTIONS
  before_action :ensure_authorized, except: COLLECTION_ACTIONS

  # GET /users/:user_id/preference
  def show
    render json: @preference, status: :ok
  end

  # PATCH/PUT /users/:user_id/preference
  def update
    @preference.attributes = preference_attributes
    if user.save
      render json: @preference, status: :ok
    else
      render_resource_errors(@preference.merged_errors)
    end
  end

  protected

    def ensure_authorized
      authorize_action_for @preference
    end

    def ensure_ready
      @preference_attributes =
      @preference_params =
      @preference =
      @user = nil
    end

    def ensure_preference
      raise Mongoid::Errors::DocumentNotFound.new(Preference, params) unless @preference.present?
    end

    def set_preference
      @preference ||= user.preference
    end

    def preference_attributes
      @preference_attributes ||= Preference.attributes_from_params(preference_params)
    end
 
    def preference_params
      @preference_params ||= Preference.json_params_for(params)
    end

    def user
      @user ||= begin
        u = User.with_email(params[:email]).first rescue nil if (params[:email] =~ Constants::EMAIL_PATTERN).present?
        u = User.find(params[:user_id]) rescue nil if u.blank? && params[:user_id].present?
        u || current_user
      end
    end

end
