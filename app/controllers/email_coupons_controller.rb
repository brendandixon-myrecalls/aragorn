class EmailCouponsController < ApplicationController

  COLLECTION_ACTIONS = COLLECTION_ACTIONS + %w(ensure)

  before_action :ensure_ready
  before_action :set_email_coupon, except: COLLECTION_ACTIONS
  before_action :ensure_email_coupon, except: COLLECTION_ACTIONS
  before_action :ensure_authorized

  after_action :send_invitation, only: [:create, :ensure]

  # GET /email_coupons
  def index
    params = search_params

    @email_coupons = EmailCoupon.in_email_order

    @email_coupons = @email_coupons.limit(params[:limit]) if params[:limit].present?
    @email_coupons = @email_coupons.offset(params[:offset]) if params[:offset].present?

    params[:related] = @email_coupons.map{|ec| ec.coupon}.uniq

    params = params.to_h.deep_symbolize_keys
    render json: EmailCoupon.as_json_collection(@email_coupons, **params), status: :ok
  end

  # POST /email_coupons
  def create
    if @email_coupon.save
      render json: @email_coupon, status: :ok
    else
      render_resource_errors(@email_coupon.merged_errors)
    end
  end

  # GET /email_coupons/:id
  def show
    render json: @email_coupon, status: :ok
  end

  # DELETE /email_coupons/:id
  def destroy
    @email_coupon.destroy
    head :no_content
  end

  protected

    def email_coupon_attributes
      @email_coupon_attributes ||= EmailCoupon.attributes_from_params(email_coupon_params)
    end

    def email_coupon_id
      @email_coupon_id ||= EmailCoupon.json_params_for(params)[:id]
    end

    def email_coupon_params
      @email_coupon_params ||= EmailCoupon.json_params_for(params)
    end

    def ensure_authorized
      return if current_user.acts_as_worker?
      raise Authority::SecurityViolation.new(current_user, self.action_name, "EmailCoupon")
    end

    def ensure_email_coupon
      raise Mongoid::Errors::DocumentNotFound.new(EmailCoupon, params) unless @email_coupon.present?
    end

    def ensure_ready
      @email_coupon =
      @email_coupon_attributes =
      @email_coupon_id =
      @email_coupon_params =
      @search_params = nil
    end

    def search_params
      @search_params ||= begin
        ensure_collection_params

        params.permit(
          :limit,
          :offset,
        )
      end
    end

    def send_invitation
      return unless @email_coupon.present? && action_succeeded?
      SendInvitationJob.perform_later(@email_coupon.email)
    end

    def set_email_coupon
      @email_coupon = if email_coupon_id.present?
        EmailCoupon.find(email_coupon_id) rescue nil
      else
        EmailCoupon.from_json(email_coupon_params)
      end
    end

end
