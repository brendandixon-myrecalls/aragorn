require 'rails_helper'
include ERB::Util

describe AdminMailer, type: :mailer do

  describe 'Sending New User Email' do

    before :example do
      @user = create(:admin)
      @mail = AdminMailer.with(user: @user).new_user_email
    end

    after :example do
      User.destroy_all
    end

    it 'includes the correct headers' do
      expect(@mail.from).to eq(['info@myrecalls.today'])
      expect(@mail.to).to eq([@user.email])
    end

  end

  describe 'Sending Reviews Needed Email' do

    before :example do
      @user = create(:admin)

      # These recalls are not yet reviewed
      @recalls = []
      7.times do 
        @recalls << create(:recall, state: 'unreviewed')
      end

      # These recalls are reviewed
      8.times do
        create(:recall)
      end

      @link = URI.join(AragornConfig.base_uri.to_s, '/review/')
      @link = html_escape(@link.to_s)

      @mail = AdminMailer.with(user: @user, recalls: @recalls).reviews_needed_email
    end

    after :example do
      Recall.destroy_all
      User.destroy_all
    end

    it 'includes the correct headers' do
      expect(@mail.from).to eq(['info@myrecalls.today'])
      expect(@mail.to).to eq([@user.email])
    end

    it 'includes the unreviewed recalls in the body' do
      @recalls.each do |r|
        expect(@mail.body.encoded).to include(r.title)
      end
    end

  end

end
