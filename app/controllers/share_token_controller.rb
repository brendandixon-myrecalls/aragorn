class ShareTokenController < ApplicationController

  skip_before_action :authenticate_user!
  before_action :set_token

  # GET /:id
  def show
    if @token.present?
      redirect_to recall_url(@token.recall_id, token: @token.token), status: :moved_permanently
    else
      raise BadRequestError.new("#{params[:id]} is not a valid token")
    end
  end

  protected

    def set_token
      params[:id] = nil unless params[:id].present? && params[:id] =~ Constants::BSON_ID_PATTERN
      params.permit(:id)
      @token = ShareToken.find(params[:id]) rescue nil
    end

end
