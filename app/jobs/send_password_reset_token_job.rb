class SendPasswordResetTokenJob < ApplicationJob
  queue_as :users

  def perform(user_id)
    @user = User.find(user_id)
    if @user.present?
      @user.send_reset_token!
      UserMailer.with(user: @user).password_reset_email.deliver_now
    end
  rescue StandardError => e
    logger.warn "Failed to send Password Reset Mail -- #{e}"
  end

end
