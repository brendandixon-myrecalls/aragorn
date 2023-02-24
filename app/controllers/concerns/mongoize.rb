module Mongoize
  extend ActiveSupport::Concern

  MONGO_WRITE_ERROR = 11000
  MONGO_UNKNOWN_ERROR = 999999

  included do
    rescue_from Mongoid::Errors::MongoidError, with: :render_mongoid_error
    rescue_from Mongo::Error, with: :render_mongo_error
  end

  protected

    def extract_mongo_code(exception)
      code = exception.code
      code = $1.to_i if code.blank? && exception.message =~ /\s*E(\d+)\s+/i
      code || MONGO_UNKNOWN_ERROR
    end

    def render_mongo_error(exception)
      error = {
        status: 500,
        title: "We're sorry, but something went wrong. We'll correct it soon!",
      }

      case extract_mongo_code(exception)
      when 11000
        error[:status] = 409
        error[:title] = "Could not create the document because it conflicts with an existing document"
      end

      Helper.log_errors("Mongo", error)
      render json: { errors: [error] }, status: error[:status]
    end

    def render_mongoid_error(exception)
      error = {
        status: 400,
        title: "Please check your request, something is not quite right.",
        detail: exception.problem,
      }
      error[:source] = exception.klass.json_params_for(params).as_json if exception.klass.present? rescue nil

      case exception
      when Mongoid::Errors::DocumentNotFound
        error[:status] = 404
        error[:title] = "We're sorry, but the requested document could not be found."
      end

      Helper.log_errors("Mongoid", error)
      render json: { errors: [error] }, status: error[:status]
    end
  
end