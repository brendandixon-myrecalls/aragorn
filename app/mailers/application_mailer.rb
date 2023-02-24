class ApplicationMailer < ActionMailer::Base
  default from: 'alerts@myrecalls.today',
          reply_to: 'no_reply@myrecalls.today'

  layout 'mailer'
end
