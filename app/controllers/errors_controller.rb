class ErrorsController < ActionController::API

  def handle_routing_error
    logger.warn("Routing Error: #{request.original_url}")
    render json: { errors: [{ status: 400, title: 'Bad request', detail: "#{request.original_url} is not recognized"}]}, status: 400
  end

end
