class SendEmailConfirmationJob < ApplicationJob
  queue_as :users

  def perform(user_id)
    @user = User.find(user_id)
    if @user.present? && !@user.email_confirmed?
      @user.send_email_token!
      UserMailer.with(user: @user).confirmation_needed_email.deliver_now
    end
  rescue StandardError => e
    logger.warn "Failed to send Email Confirmation Mail -- #{e}"
  end

end
