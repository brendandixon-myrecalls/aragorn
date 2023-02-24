class AuthenticationController < ApplicationController

  skip_before_action :authenticate_user!, only: [:clear_password, :set_password, :sign_in]

  before_action :ensure_ready

  # POST /signin
  def sign_in
    user = User.find_by(email: auth_params[:email])

    raise if user.account_locked?
    raise unless user.authenticate(auth_params[:password])

    user.ensure_access_token!
    render_token_response(user)
  rescue
    if user
      raise Authentication::LockedAccountError.new if user.account_locked?
      user.authentication_failed!
    end
    raise Authentication::AuthenticationError.new
  end

  # DELETE /sign_out
  def sign_out
    current_user.clear_access_token!
    head :ok
  rescue
    raise Authentication::AuthenticationError.new
  end

  # GET /refresh
  def refresh
    current_user.refresh_access_token!
    render_token_response(current_user)
  rescue
    raise Authentication::AuthenticationError.new
  end

  # GET /confirm?email or /confirm?phone
  def send_confirmation
    if auth_params.has_key?(:email)
      current_user.email_unconfirmed!
    elsif auth_params.has_key?(:phone)
      current_user.phone_unconfirmed!
    else
      raise BadRequestError.new('Failed to specify email or phone')
    end
    head :ok
  end

  # POST /confirm
  def confirm
    if current_user.is_email_token?(auth_params[:token])
      current_user.email_confirmed!
    elsif current_user.is_phone_token?(auth_params[:token])
      current_user.phone_confirmed!
    else
      raise BadRequestError.new('Confirmation token is not valid')
    end
    head :ok
  end

  # GET /reset
  def clear_password
    ua = unauthenticated_user
    raise unless ua.present?

    params = recaptcha_params
    raise unless verify_recaptcha(response: params[:recaptcha])

    unauthenticated_user.reset_password!
    head :ok
  rescue Mongoid::Errors::Validations => e
    logger.warn("Validation errors while clearing password for #{ua.email}: #{ua.merged_errors.full_messages.join(', ')}")
    raise BadRequestError.new("Your account needs assistance. Please contact support.")
  rescue StandardError => e
    logger.warn("Unexpected error clearing password for #{ua.email}: #{e}") if ua.present?
    raise Authentication::AuthenticationError.new
  end

  # POST /reset
  def set_password
    ua = unauthenticated_user
    token_passes = ua.present? && ua.is_reset_token?(auth_params[:token])
    raise unless token_passes

    unauthenticated_user.password = auth_params[:password]
    unauthenticated_user.save!
    unauthenticated_user.unlock_account!
    head :ok
  rescue Mongoid::Errors::Validations => e
    logger.warn("Validation errors while setting password for #{ua.email}: #{ua.merged_errors.full_messages.join(', ')}")
    raise BadRequestError.new("Your account needs assistance. Please contact support.")
  rescue StandardError => e
    logger.warn("Unexpected error setting password for #{ua.email}: #{e}") if token_passes
    raise Authentication::AuthenticationError.new
  end

  # GET /validate
  def validate
    head :ok
  end

  protected

    def ensure_ready
      @auth_params =
      @unauthenticated_user = nil
    end
 
    def auth_params
      @auth_params ||= begin

        params[:email] = User.normalize_email(params[:email]) if params[:email].present?
        params[:password] = User.normalize_password(params[:password]) if params[:password].present?
        params[:token] = params[:token].squish if params[:token].is_a?(String)

        params.permit(:email, :password, :phone, :token)
      end
    end

    def render_token_response(user)
      response = {
        accessToken: user.access_token,
        tokenType: 'Bearer',
        expiresAt: JsonWebToken.expires_at(user.access_token).to_i,
        userId: user.id.to_s,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
        role: user.role,
      }
      render json: response, status: :ok
    end

    def unauthenticated_user
      @unauthenticated_user ||= if auth_params[:email].present?
        begin
          User.find_by(email: auth_params[:email].downcase)
        rescue MongoidError => e
          nil
        end
      elsif current_user.present?
        current_user
      else
        authenticate_user!
        current_user
      end
    end

end
