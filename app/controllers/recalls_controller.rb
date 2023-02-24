class RecallsController < ApplicationController

  COLLECTION_ACTIONS = COLLECTION_ACTIONS + %w(mark_all_sent summary)

  authorize_actions_for Recall, only: COLLECTION_ACTIONS
  authority_actions summary: :read
  authority_actions mark_sent: :update
  authority_actions mark_all_sent: :update

  before_action :ensure_ready
  before_action :set_recall, except: COLLECTION_ACTIONS
  before_action :ensure_recall, except: COLLECTION_ACTIONS
  before_action :ensure_authorized, except: COLLECTION_ACTIONS
  before_action :validate_token, only: [:show]

  after_action :send_alerts, only: [:create, :update]
  after_action :send_review_needed, only: [:create]
  after_action :upload, only: [:create, :mark_sent, :mark_all_sent, :update]

  # GET /recalls
  def index
    params = search_params

    @recalls = Recall.in_published_order(params[:sort] == :asc)

    @recalls = @recalls.has_id(params[:recalls]) if params[:recalls].present?

    @recalls = @recalls.includes_names(params[:names]) if params[:names].present?
    @recalls = @recalls.excludes_names(params[:xnames]) if params[:xnames].present?

    @recalls = @recalls.includes_sources(params[:sources]) if params[:sources].present?
    @recalls = @recalls.excludes_sources(params[:xsources]) if params[:xsources].present?

    @recalls = @recalls.published_after(params[:after]) if params[:after].present?
    @recalls = @recalls.published_before(params[:before]) if params[:before].present?

    @recalls = @recalls.includes_affected(params[:affects]) if params[:affects].present?
    @recalls = @recalls.includes_allergens(params[:allergens]) if params[:allergens].present?
    @recalls = @recalls.includes_audience(params[:audience]) if params[:audience].present?
    @recalls = @recalls.includes_categories(params[:categories]) if params[:categories].present?
    @recalls = @recalls.includes_contaminants(params[:contaminants]) if params[:contaminants].present?
    @recalls = @recalls.includes_distribution(params[:distribution]) if params[:distribution].present?
    @recalls = @recalls.includes_risk(params[:risk]) if params[:risk].present?

    @recalls = @recalls.excludes_affected(params[:xaffects]) if params[:xaffects].present?
    @recalls = @recalls.excludes_allergens(params[:xallergens]) if params[:xallergens].present?
    @recalls = @recalls.excludes_audience(params[:xaudience]) if params[:xaudience].present?
    @recalls = @recalls.excludes_categories(params[:xcategories]) if params[:xcategories].present?
    @recalls = @recalls.excludes_contaminants(params[:xcontaminants]) if params[:xcontaminants].present?
    @recalls = @recalls.excludes_distribution(params[:xdistribution]) if params[:xdistribution].present?
    @recalls = @recalls.excludes_risk(params[:xrisk]) if params[:xrisk].present?

    @recalls = @recalls.in_state(params[:state]) if params[:state].present?

    @recalls = @recalls.limit(params[:limit]) if params[:limit].present?
    @recalls = @recalls.offset(params[:offset]) if params[:offset].present?

    params = params.to_h.deep_symbolize_keys
    render json: Recall.as_json_collection(@recalls, **params), status: :ok
  end

  # POST /recalls
  def create
    if (Recall.find(@recall.id) rescue nil).present?
      redirect_to recall_url(@recall.id), status: :see_other
    elsif @recall.save
      render json: @recall, status: :created
    else
      render_resource_errors(@recall.merged_errors)
    end
  end

  # GET /recalls/:id
  def show
    render json: @recall, status: :ok
  end

  # PATCH/PUT /recalls/:id
  def update
    if @recall.update_attributes(recall_attributes)
      render json: @recall, status: :ok
    else
      render_resource_errors(@recall.merged_errors)
    end
  end

  # PATCH/PUT /recalls/:id/sent
  def mark_sent
    @recall.sent!
    head :ok
  end

  # PATCH/PUT /recalls/sent
  def mark_all_sent
    @recalls = Recall.needs_sending.to_a
    @recalls.each{|r| r.sent!}
    head :ok
  end

  # GET /recalls/summary
  def summary
    params = summary_params

    @recalls = Recall.in_published_order.was_sent

    params[:after] = 1.month.ago unless params[:after].present?
    params[:after] = params[:after].beginning_of_day.utc

    params[:before] = Time.now unless params[:before].present?
    params[:before] = params[:before].end_of_day.utc

    @recalls = @recalls.published_after(params[:after])
    @recalls = @recalls.published_before(params[:before])

    summary = {
      total: @recalls.count,
      risk: FeedConstants::RISK.inject({}){|o, r| o[r] = 0; o},
      categories: FeedConstants::PUBLIC_CATEGORIES.inject({}){|o, c| o[c] = 0; o}
    }

    @recalls.each do |recall|
      categories = recall.categories & FeedConstants::PUBLIC_CATEGORIES
      risk = [recall.risk] & FeedConstants::RISK

      logger.info "Recall #{recall.id} had unexpected categories (#{recall.categories})" unless categories.present?
      logger.info "Recall #{recall.id} had unexpected risk (#{recall.risk})" unless risk.present?
      next unless categories.present? && risk.present?

      categories.each{|category| summary[:categories][category] += 1}
      summary[:risk][recall.risk] += 1
    end

    render json: JsonEnvelope.new(Recall, path: :summary, data: summary), status: :ok
  end

  # DELETE /recalls/:id
  def destroy
    @recall.destroy
    head :no_content
  end

  protected

    def ensure_authorized
      authorize_action_for @recall

      return if !@recall.sent? || current_user.acts_as_admin? || !recall_attributes.has_key?(:state)
      raise Authority::SecurityViolation.new(current_user, self.action_name, @recall) if recall_attributes[:state] != 'sent'
    end

    def ensure_ready
      @recall_attributes =
      @recall_id =
      @recall_params =
      @search_params = nil
    end

    def ensure_recall
      raise Mongoid::Errors::DocumentNotFound.new(Recall, params) unless @recall.present?
    end

    def is_token_valid?
      return false unless @recall.present? && !@recall.new_record? && @recall.sent?
      @recall.token == token_params[:token]
    end

    def recall_attributes
      @recall_attributes ||= Recall.attributes_from_params(recall_params)
    end

    def recall_id
      @recall_id ||= Recall.json_params_for(params)[:id]
    end

    def recall_params
      @recall_params ||= Recall.json_params_for(params)
    end

    def search_params
      @search_params ||= begin
        ensure_collection_params

        # Note:
        # - Limit recalls to those of the most current recall subscription
        unless current_user.has_recall_subscription?
          params[:before] = current_user.subscriptions.filter{|s| s.recalls?}.max{|s1, s2| s1.expiration <=> s2.expiration}.expiration
        end

        params[:after] = Constants::MINIMUM_RECALL_DATE if params[:after].blank? || params[:after] < Constants::MINIMUM_RECALL_DATE

        params[:recalls] = params[:recalls].split(',').map{|id| id =~ Recall::ID_PATTERN ? id : nil}.compact if params[:recalls].present?

        params[:names] = params[:names].split(',') & FeedConstants::NAMES if params[:names].present?
        params[:xnames] = params[:xnames].split(',') & FeedConstants::NAMES if params[:xnames].present?

        params[:sources] = params[:sources].split(',') & FeedConstants::SOURCES if params[:sources].present?
        params[:xsources] = params[:xsources].split(',') & FeedConstants::SOURCES if params[:xsources].present?

        params[:affects] = params[:affects].split(',') & FeedConstants::AFFECTED if params[:affects].present?
        params[:allergens] = params[:allergens].split(',') & FeedConstants::FOOD_ALLERGENS if params[:allergens].present?
        params[:audience] = params[:audience].split(',') & FeedConstants::AUDIENCE if params[:audience].present?
        params[:categories] = params[:categories].split(',') & FeedConstants::ALL_CATEGORIES if params[:categories].present?
        params[:contaminants] = params[:contaminants].split(',') & FeedConstants::ALL_CONTAMINANTS if params[:contaminants].present?
        params[:distribution] = params[:distribution].split(',') & USRegions::ALL_STATES if params[:distribution].present?
        params[:risk] = params[:risk].split(',') & FeedConstants::RISK if params[:risk].present?

        params[:xaffects] = params[:xaffects].split(',') & FeedConstants::AFFECTED if params[:xaffects].present?
        params[:xallergens] = params[:xallergens].split(',') & FeedConstants::FOOD_ALLERGENS if params[:xallergens].present?
        params[:xaudience] = params[:xaudience].split(',') & FeedConstants::AUDIENCE if params[:xaudience].present?
        params[:xcategories] = params[:xcategories].split(',') & FeedConstants::ALL_CATEGORIES if params[:xcategories].present?
        params[:xcontaminants] = params[:xcontaminants].split(',') & FeedConstants::ALL_CONTAMINANTS if params[:xcontaminants].present?
        params[:xdistribution] = params[:xdistribution].split(',') & USRegions::ALL_STATES if params[:xdistribution].present?
        params[:xrisk] = params[:xrisk].split(',') & FeedConstants::RISK if params[:xrisk].present?

        if current_user.acts_as_worker?
          params[:state] = params[:state].split(',') & Recall::STATES if params[:state].present?
        else
          params[:state] = ['sent']
          params[:xnames] = (params[:xnames] || []) + FeedConstants::NONPUBLIC_NAMES
          params[:xsources] = (params[:xsources] || []) + FeedConstants::NONPUBLIC_SOURCES
        end

        params.permit(
          :after,
          :before,
          :limit,
          :offset,
          :sort,
          state: [],

          recalls:[],

          names:[],
          xnames:[],

          sources:[],
          xsources:[],

          affects:[],
          allergens:[],
          audience: [],
          categories:[],
          contaminants:[],
          distribution:[],
          risk:[],

          xaffects:[],
          xallergens:[],
          xaudience: [],
          xcategories:[],
          xcontaminants:[],
          xdistribution:[],
          xrisk:[],
        )
      end
    end

    def send_alerts
      return unless self.action_succeeded?
      return if Recall.needs_review.exists?
      return unless Recall.needs_sending.exists?
      SendAlertsJob.perform_later("send_recall_alerts")

    rescue StandardError => e
      logger.error("Failed to assign users for Recall #{@recall.id}")
    end

    def set_recall
      @recall = if recall_id.present?
          Recall.find(recall_id) rescue nil
        else
          Recall.from_json(recall_params)
        end
    end

    def send_review_needed
      SendReviewNeededJob.perform_later if self.action_succeeded? && !@recall.reviewed?
    end

    def summary_params
      @summary_params ||= begin
        ensure_collection_params

        params[:after] = Constants::MINIMUM_RECALL_DATE if params[:after].present? && params[:after] < Constants::MINIMUM_RECALL_DATE

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

    def validate_token
      return unless current_user.is_guest?
      raise Authentication::AuthenticationError.new unless is_token_valid?
      @recall.share_token.accessed!
    end

end
