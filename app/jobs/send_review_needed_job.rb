class SendReviewNeededJob < ApplicationJob
  queue_as :admin

  def perform
    @recalls = Recall.needs_review
    @users = User.is_admin
    @users.each do |user|
      AdminMailer.with(user: user, recalls: @recalls).reviews_needed_email.deliver_now
    end if @recalls.present?
  rescue StandardError => e
    logger.warn "Failed to send Recall Review Mail -- #{e}"
  end

end
