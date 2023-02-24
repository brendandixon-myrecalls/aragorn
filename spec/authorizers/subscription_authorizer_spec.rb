require 'rails_helper'

describe SubscriptionAuthorizer, type: :authorizer do

  before :example do
    @admin = create(:admin)
    @worker = create(:worker)
    @user = create(:user)
    @subscription = @user.subscriptions.first
    expect(@subscription).to be_present
  end

  after :example do
    User.destroy_all
  end

  context "for an Admin" do

    it 'allows creation' do
      expect(@subscription.authorizer).to be_creatable_by(@admin)
    end

    it 'allows reading' do
    end

    it 'allows reading the collection' do
      expect(SubscriptionAuthorizer).to be_readable_by(@admin)
    end

    it 'allows updating' do
      expect(@subscription.authorizer).to be_updatable_by(@admin)
    end

    it 'allows deletion' do
      expect(@subscription.authorizer).to be_deletable_by(@admin)
    end

  end

  context "for a User" do

    it 'allows creation' do
      expect(@subscription.authorizer).to be_creatable_by(@user)
    end

    it 'allows reading' do
    end

    it 'allows reading the collection' do
      expect(SubscriptionAuthorizer).to be_readable_by(@user)
    end

    it 'allows updating' do
      expect(@subscription.authorizer).to be_updatable_by(@user)
    end

    it 'disallows deletion' do
      expect(@subscription.authorizer).to_not be_deletable_by(@user)
    end

  end

  context "for a Worker" do

    it 'allows creation' do
      expect(@subscription.authorizer).to be_creatable_by(@worker)
    end

    it 'allows reading' do
    end

    it 'allows reading the collection' do
      expect(SubscriptionAuthorizer).to be_readable_by(@worker)
    end

    it 'allows updating' do
      expect(@subscription.authorizer).to be_updatable_by(@worker)
    end

    it 'allows deletion' do
      expect(@subscription.authorizer).to be_deletable_by(@worker)
    end

  end

end
