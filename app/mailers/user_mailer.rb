class UserMailer < ApplicationMailer

  default from: 'info@myrecalls.today',
          reply_to: 'no_reply@myrecalls.today'

  before_action { @user = params[:user] }
  before_action { @email = params[:email] || (@user.present? ? @user.email : nil) }

  def confirmation_needed_email
    @link = URI.join(AragornConfig.base_uri, "/account/?confirm=email&token=#{@user.email_confirmation_token}")
    mail(to: @email, subject: 'Please confirm your myRecalls email')
  end

  def invitation_email
    mail(to: @email, subject: 'You are invited to join myRecalls!')
  end

  def password_reset_email
    @link = URI.join(AragornConfig.base_uri, "/password/set/?token=#{@user.reset_password_token}")
    mail(to: @email, subject: 'Please reset your myRecalls password')
  end

end
