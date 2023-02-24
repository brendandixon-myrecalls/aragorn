require 'rails_helper'

describe UserAuthorizer, type: :authorizer do

  before :example do
    @admin = create(:admin)
    @worker = create(:worker)
    @recall = create(:recall, feed_name: 'cpsc')
    @user = create(:user)
    @newbie = create(:user)
    @nonpublic = FeedConstants::NONPUBLIC_NAMES.map{|fn| create(:recall, feed_name: fn)}
  end

  after :example do
    Recall.destroy_all
    User.destroy_all
  end

  context "for an Admin" do

    it 'allows creation' do
      expect(@admin.authorizer).to be_creatable_by(@admin)
      expect(build(:user).authorizer).to be_creatable_by(@admin)
    end

    it 'allows reading the user' do
      expect(@admin.authorizer).to be_readable_by(@admin)
    end

    it 'allows reading another user' do
      expect(@user.authorizer).to be_readable_by(@admin)
    end

    it 'allows reading the collection' do
      expect(UserAuthorizer).to be_readable_by(@admin)
    end

    it 'allows updating the collection' do
      expect(UserAuthorizer).to be_updatable_by(@admin)
    end

    it 'allows updating the user' do
      expect(@admin.authorizer).to be_updatable_by(@admin)
    end

    it 'allows updating another user' do
      expect(@user.authorizer).to be_updatable_by(@admin)
    end

    it 'disallows deletion of the user' do
      expect(@admin.authorizer).to_not be_deletable_by(@admin)
    end

    it 'allows deletion of another user' do
      expect(@user.authorizer).to be_deletable_by(@admin)
    end
  end

  context "for a User" do

    it 'disallows creation' do
      expect(@user.authorizer).to_not be_creatable_by(@user)
      expect(@newbie.authorizer).to_not be_creatable_by(@user)
      expect(build(:user).authorizer).to_not be_creatable_by(@user)
    end

    it 'allows reading the user' do
      expect(@user.authorizer).to be_readable_by(@user)
    end

    it 'allows reading the user even if the plan is expired' do
      expire_all!(@user)
      expect(@user.authorizer).to be_readable_by(@user)
    end

    it 'disallows reading another user' do
      expect(@newbie.authorizer).to_not be_readable_by(@user)
    end

    it 'disallows reading the collection' do
      expect(UserAuthorizer).to_not be_readable_by(@user)
    end

    it 'allows updating the user' do
      expect(@user.authorizer).to be_updatable_by(@user)
    end

    it 'disallows updating the collection' do
      expect(UserAuthorizer).to_not be_updatable_by(@user)
    end

    it 'allows updating the user even if the plan is expired' do
      expire_all!(@user)
      expect(@user.authorizer).to be_readable_by(@user)
    end

    it 'disallows updating another user' do
      expect(@newbie.authorizer).to_not be_updatable_by(@user)
    end

    it 'disallows deletion of the user' do
      expect(@user.authorizer).to_not be_deletable_by(@user)
    end

    it 'disallows deletion of another user' do
      expect(@newbie.authorizer).to_not be_deletable_by(@user)
    end

  end

  context "for a Worker" do

    it 'allows creation' do
      expect(@user.authorizer).to be_creatable_by(@worker)
      expect(@worker.authorizer).to be_creatable_by(@worker)
      expect(build(:user).authorizer).to be_creatable_by(@worker)
    end

    it 'allows reading the user' do
      expect(@worker.authorizer).to be_readable_by(@worker)
    end

    it 'allows reading another user' do
      expect(@user.authorizer).to be_readable_by(@worker)
    end

    it 'allows reading the collection' do
      expect(UserAuthorizer).to be_readable_by(@worker)
    end

    it 'allows updating the user' do
      expect(@worker.authorizer).to be_updatable_by(@worker)
    end

    it 'allows updating the collection' do
      expect(UserAuthorizer).to be_updatable_by(@worker)
    end

    it 'allows updating another user' do
      expect(@user.authorizer).to be_updatable_by(@worker)
    end

    it 'disallows deletion of the user' do
      expect(@worker.authorizer).to_not be_deletable_by(@worker)
    end

    it 'allows deletion of another user' do
      expect(@user.authorizer).to be_deletable_by(@worker)
    end

  end

end
