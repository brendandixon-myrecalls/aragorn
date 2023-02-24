class VehicleRecallsController < ApplicationController

  COLLECTION_ACTIONS = COLLECTION_ACTIONS + %w(mark_all_sent summary)

  authorize_actions_for VehicleRecall, only: COLLECTION_ACTIONS
  authority_actions mark_sent: :update
  authority_actions mark_all_sent: :update
  authority_actions summary: :read

  before_action :ensure_ready
  before_action :set_recall, except: COLLECTION_ACTIONS
  before_action :ensure_recall, except: COLLECTION_ACTIONS
  before_action :ensure_authorized, except: COLLECTION_ACTIONS

  after_action :send_alerts, only: [:create, :update]
  after_action :upload, only: [:create, :mark_sent, :mark_all_sent, :update]

  # GET /vehicle_recalls
  def index
    params = search_params

    @recalls = VehicleRecall.in_published_order(params[:sort] == :asc)

    @recalls = @recalls.has_id(params[:recalls]) if params[:recalls].present?

    @recalls = @recalls.published_after(params[:after]) if params[:after].present?
    @recalls = @recalls.published_before(params[:before]) if params[:before].present?

    @recalls = @recalls.for_campaigns(params[:campaigns]) if params[:campaigns].present?
    @recalls = @recalls.for_vkeys(params[:vkeys]) if params[:vkeys].present?
    @recalls = @recalls.in_state(params[:state]) if params[:state].present?

    @recalls = @recalls.limit(params[:limit]) if params[:limit].present?
    @recalls = @recalls.offset(params[:offset]) if params[:offset].present?

    params = params.to_h.deep_symbolize_keys
    render json: VehicleRecall.as_json_collection(@recalls, **params), status: :ok
  end

  # POST /vehicle_recalls
  def create
    vr = VehicleRecall.for_campaigns(@recall.campaign_id)
    if vr.exists?
      redirect_to vehicle_recall_url(vr.first.id), status: :see_other
    elsif @recall.save
      render json: @recall, status: :created
    else
      render_resource_errors(@recall.merged_errors)
    end
  end

  # GET /vehicle_recalls/:id
  def show
    render json: @recall, status: :ok
  end

  # PATCH/PUT /vehicle_recalls/:id
  def update
    if @recall.update_attributes(recall_attributes)
      render json: @recall, status: :ok
    else
      render_resource_errors(@recall.merged_errors)
    end
  end

  # PATCH/PUT /vehicle_recalls/:id/sent
  def mark_sent
    @recall.sent!
    head :ok
  end

  # PATCH/PUT /vehicle_recalls/sent
  def mark_all_sent
    @recalls = VehicleRecall.needs_sending.to_a
    @recalls.each{|r| r.sent!}
    head :ok
  end

  # DELETE /vehicle_recalls/:id
  def destroy
    @recall.destroy
    head :no_content
  end

  # GET /vehicle_recalls/summary
  def summary
    params = summary_params

    @recalls = VehicleRecall.in_published_order

    params[:after] = Time.now.prev_month.beginning_of_month unless params[:after].present?
    params[:after] = params[:after].beginning_of_day.utc

    params[:before] = Time.now.prev_month.end_of_month unless params[:before].present?
    params[:before] = params[:before].end_of_day.utc

    @recalls = @recalls.published_after(params[:after])
    @recalls = @recalls.published_before(params[:before])

    # TODO: Handle an excessive number of impacted users
    vkeys = @recalls.map{|r| r.vkeys}.flatten.uniq
    summary = {
      total: @recalls.count,
      totalAffectedVehicles: vkeys.count,
      impactedUsers: User.has_interest_in_vkey(vkeys).map{|u| u.id.to_s}
    }

    render json: JsonEnvelope.new(VehicleRecall, path: :summary, data: summary), status: :ok
  end

  protected

    def campaign_id
      @campaign_id ||= params[:campaign_id] if (params[:campaign_id] || '') =~ Constants::CAMPAIGN_ID_PATTERN
    end

    def ensure_authorized
      authorize_action_for @recall

      return if !@recall.sent? || current_user.acts_as_admin? || !recall_attributes.has_key?(:state)
      raise Authority::SecurityViolation.new(current_user, self.action_name, @recall) if recall_attributes[:state] != 'sent'
    end

    def ensure_ready
      @campaign_id =
      @recall_attributes =
      @recall_id =
      @recall_params =
      @search_params = nil
    end

    def ensure_recall
      raise Mongoid::Errors::DocumentNotFound.new(VehicleRecall, params) unless @recall.present?
    end

    def recall_attributes
      @recall_attributes ||= VehicleRecall.attributes_from_params(recall_params)
    end

    def recall_id
      @recall_id ||= VehicleRecall.json_params_for(params)[:id]
    end

    def recall_params
      @recall_params ||= VehicleRecall.json_params_for(params)
    end

    def search_params
      @search_params ||= begin
        ensure_collection_params

        params[:after] = Constants::MINIMUM_VEHICLE_DATE if params[:after].blank? || params[:after] < Constants::MINIMUM_VEHICLE_DATE

        params[:recalls] = params[:recalls].split(',').map{|id| id =~ Constants::BSON_ID_PATTERN ? id : nil}.compact if params[:recalls].present?

        params[:campaigns] = params[:campaigns].split(',').map{|id| id =~ Vehicles::CAMPAIGN_REGEX ? id : nil}.compact if params[:campaign].present?
        params[:vkeys] = Array(params[:vkeys]).map{|id| id =~ Vehicles::VKEY_REGEX ? id : nil}.compact if params[:vkeys].present?
        params[:state] = params[:state].split(',') & VehicleRecall::STATES if params.has_key?(:state)

        params.permit(
          :after,
          :before,
          :limit,
          :offset,
          :sort,

          recalls:[],
          campaigns: [],
          vkeys: [],
          state: [],
        )
      end
    end

    def send_alerts
      return unless self.action_succeeded?
      return unless VehicleRecall.needs_sending.exists?
      SendAlertsJob.perform_later("send_vehicle_recall_alerts")

    rescue StandardError => e
      logger.error("Failed to assign users for VehicleRecall #{@recall.id}")
    end

    def set_recall
      @recall = if recall_id.present?
          VehicleRecall.find(recall_id) rescue nil
        elsif campaign_id.present?
          VehicleRecall.for_campaign(campaign_id).first rescue nil
        else
          VehicleRecall.from_json(recall_params)
        end
    end

    def summary_params
      @summary_params ||= begin
        ensure_collection_params

        params[:after] = Constants::MINIMUM_VEHICLE_DATE if params[:after].present? && params[:after] < Constants::MINIMUM_VEHICLE_DATE

        params.permit(
          :after,
          :before,
          :limit,
          :offset,
        )
      end
    end

    def upload
      return unless self.action_succeeded?
      (@recalls || [@recall]).each do |r|
        AwsHelper.upload_recall(r)
      end
    end

end
