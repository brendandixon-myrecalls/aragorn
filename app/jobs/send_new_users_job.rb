class SendNewUsersJob < ApplicationJob
  queue_as :admin

  def perform
    User.is_admin.each do |user|
      AdminMailer.with(user: user).new_user_email.deliver_now
    end
  rescue StandardError => e
    logger.warn "Failed to send New User Mail -- #{e}"
  end

end
