module Authentication
  extend ActiveSupport::Concern
  include Authority::Controller

  class AuthenticationError < StandardError
  end

  class LockedAccountError < AuthenticationError
  end

  included do

    rescue_from Authentication::AuthenticationError, with: :render_authentication_error
    rescue_from Authentication::LockedAccountError, with: :render_authentication_error

    rescue_from Authority::MissingUser, with: :render_authorization_error
    rescue_from Authority::SecurityViolation, with: :render_authorization_error

    before_action :prepare_authentication
    before_action :authenticate_user!

  end

  protected

    def access_token
      @access_token ||= begin
        h = request.headers['Authorization']
        (h || '').split(' ').last
      end
    end

    def authenticate_user!
      raise Authentication::AuthenticationError.new if current_user.blank?
    end

    def authority_forbidden(e)
      render_authorization_error(e)
    end

    def current_user
      @current_user ||= begin
        u = User.from_access_token(access_token)
        if u.present?
          raise Authentication::LockedAccountError.new if u.account_locked?
        elsif token_params[:token].present?
          u = User.guest_user
        end
        u
      end
    end

    def prepare_authentication
      @access_token =
      @current_user =
      @recaptcha_params =
      @token_params = nil
    end

    def recaptcha_params
      @recaptcha_params ||= begin
        raise unless params[:recaptcha].present?
        
        params.permit(
          :recaptcha
        )
      end
    end

    def render_authentication_error(e)
      detail = e.is_a?(Authentication::LockedAccountError) ? 'The account is locked' : nil
      render json: ::JsonEnvelope.as_error(401, 'Unauthorized', detail), status: :unauthorized
    end

    def render_authorization_error(e)
      detail = if e.is_a?(Authority::MissingUser)
        'You must sign-in to complete the request'
      else
        e.message.present? ? e.message : 'You are not allowed to complete the request'
      end
      render json: ::JsonEnvelope.as_error(403, 'Forbidden', detail), status: :forbidden
    end

    def token_params
      @token_params ||= begin
        params[:token] = nil unless params[:token].present? && params[:token] =~ Constants::BSON_ID_PATTERN
        params.permit(
          :token
        )
      end
    end

end
