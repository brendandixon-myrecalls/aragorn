class PlansController < ApplicationController

  skip_before_action :authenticate_user!, only: [:index]

  before_action :ensure_ready

  # GET /plans
  def index
    params = {}

    c = EmailCoupon.coupon_for_email(email) if email.present?
    params[:related] = [c] if c.present?

    render json: Plan.as_json_collection(Plan.all, **params), status: :ok
  end

  protected

    def email
      @email ||= begin
        e = params[:email] if user.present? && user.acts_as_worker? && (params[:email] =~ Constants::EMAIL_PATTERN).present?
        e || (user.present? ? user.email : nil)
      end
    end

    def ensure_ready
      @email = nil
    end

    def user
      @user ||= begin
        current_user
      end
    end

end
