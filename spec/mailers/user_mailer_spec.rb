require 'rails_helper'
include ERB::Util

describe UserMailer, type: :mailer do

  describe 'Sending Confirmation Email' do

    before :example do
      @user = create(:user)
      @user.email_unconfirmed!

      @link = URI.join(AragornConfig.base_uri, "/account/?confirm=email&token=#{@user.email_confirmation_token}")
      @link = html_escape(@link.to_s)
      @mail = UserMailer.with(user: @user).confirmation_needed_email
    end

    after :example do
      User.destroy_all
    end

    it 'includes the correct headers' do
      expect(@mail.from).to eq(['info@myrecalls.today'])
      expect(@mail.to).to eq([@user.email])
    end

    it 'includes the User email in the body' do
      expect(@mail.body.encoded).to match(@user.email)
    end

    it 'includes the confirmation link in the body' do
      expect(@mail.body.to_s).to include(@link)
    end

  end

  describe 'Sending Invitation Email' do

    before :example do
      @email = 'fauxuser@nomail.com'
      @link = 'https://myrecalls.today/signup'
      @link = html_escape(@link.to_s)
      @mail = UserMailer.with(email: @email).invitation_email
    end

    after :example do
      User.destroy_all
    end

    it 'includes the correct headers' do
      expect(@mail.from).to eq(['info@myrecalls.today'])
      expect(@mail.to).to eq([@email])
    end

    it 'includes the User email in the body' do
      expect(@mail.body.encoded).to match(@email)
    end

    it 'includes the signup link in the body' do
      expect(@mail.body.to_s).to include(@link)
    end

  end

  describe 'Sending Password Reset Email' do

    before :example do
      @user = create(:user)
      @user.reset_password!

      @link = URI.join(AragornConfig.base_uri, "/password/set/?token=#{@user.reset_password_token}")
      @link = html_escape(@link.to_s)
      @mail = UserMailer.with(user: @user).password_reset_email
    end

    after :example do
      User.destroy_all
    end

    it 'includes the correct headers' do
      expect(@mail.from).to eq(['info@myrecalls.today'])
      expect(@mail.to).to eq([@user.email])
    end

    it 'includes the User email in the body' do
      expect(@mail.body.encoded).to match(@user.email)
    end

    it 'includes the password reset link in the body' do
      expect(@mail.body.to_s).to include(@link)
    end

    it 'includes explanatory text if the User account is locked' do
      @user.lock_account!
      expect(@mail.body.encoded).to match('Your myRecalls account has been locked!')
    end

  end

end
