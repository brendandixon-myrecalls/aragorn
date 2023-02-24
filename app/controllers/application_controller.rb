class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  include Authentication
  include Mongoize
  
  rescue_from BadRequestError, with: :render_bad_request

  COLLECTION_ACTIONS = %w(index)

  protected

    def action_succeeded?
      (200...300).include?(response.status)
    end

    def is_collection_action?
      self.class::COLLECTION_ACTIONS.include?(self.action_name)
    end

    def render_bad_request(e)
      render json: ::JsonEnvelope.as_error(400, 'Bad Request', e.to_s), status: :bad_request
    end

    def render_resource_errors(errors)
      je = JsonEnvelope.new
      errors.full_messages.each do |message|
        je.add_error(409, 'Validation failed', message)
      end

      render json: je, status: :conflict
    end

    def ensure_collection_params
      params.with_defaults!({
        limit: Constants::DEFAULT_PAGE_SIZE,
        offset: 0
      })

      params[:after] = (Time.parse(params[:after]).at_beginning_of_minute rescue nil) if params[:after].present?
      params[:before] = (Time.parse(params[:before]).at_end_of_minute rescue nil) if params[:before].present?

      params[:limit] = params[:limit].to_i
      params[:limit] = Constants::MAXIMUM_PAGE_SIZE unless (1..Constants::MAXIMUM_PAGE_SIZE).include?(params[:limit])

      params[:offset] = params[:offset].to_i
      params[:offset] = 0 if params[:offset] < 0

      params[:sort] = :asc if params[:sort] =~ /asc/i
      params[:sort] = :desc if params[:sort] =~ /desc/i
    end

  end
