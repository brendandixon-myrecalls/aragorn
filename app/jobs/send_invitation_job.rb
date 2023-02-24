class SendInvitationJob < ApplicationJob
  queue_as :users

  def perform(email)
    UserMailer.with(email: email).invitation_email.deliver_now
  rescue StandardError => e
    logger.warn "Failed to send Invitation Email to #{email} -- #{e}"
  end

end
