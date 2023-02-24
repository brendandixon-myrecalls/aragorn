class AdminMailer < ApplicationMailer

  default from: 'info@myrecalls.today',
          reply_to: 'no_reply@myrecalls.today'

  before_action { @user = params[:user] }
  before_action { @email = params[:email] || @user.email }

  def reviews_needed_email
    @recalls = params[:recalls]
    @link = URI.join(AragornConfig.base_uri.to_s, '/review/')
    mail(to: @email, subject: 'MyRecalls Pending Reviews')
  end

  def new_user_email
    mail(to: @email, subject: 'New myRecalls Users')
  end

end
