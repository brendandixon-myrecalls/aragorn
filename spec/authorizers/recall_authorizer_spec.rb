require 'rails_helper'

describe RecallAuthorizer, type: :authorizer do

  before :example do
    @admin = create(:admin)
    @worker = create(:worker)
    @recall = create(:recall, feed_name: 'cpsc')
    @user = create(:user)
    @nonpublic = FeedConstants::NONPUBLIC_NAMES.map{|fn| create(:recall, feed_name: fn)}
  end

  after :example do
    Recall.destroy_all
    User.destroy_all
  end

  context "for an Admin" do

    it 'allows creation' do
      expect(@recall.authorizer).to be_creatable_by(@admin)
      expect(build(:recall).authorizer).to be_creatable_by(@admin)
    end

    it 'allows reading' do
      expect(@recall.authorizer).to be_readable_by(@admin)
    end

    it 'allows reading the collection' do
      expect(Recall.authorizer).to be_readable_by(@admin)
    end

    it 'allows reading non-public feeds' do
      @nonpublic.each do |r|
        expect(r.authorizer).to be_readable_by(@admin)
      end
    end

    it 'allows reading the collection' do
      expect(RecallAuthorizer).to be_readable_by(@admin)
    end

    it 'allows updating' do
      expect(@recall.authorizer).to be_updatable_by(@admin)
    end

    it 'allows updating the collection' do
      expect(Recall.authorizer).to be_updatable_by(@admin)
    end

    it 'allows deletion' do
      expect(@recall.authorizer).to be_deletable_by(@admin)
    end

  end

  context "for a User" do

    it 'disallows creation' do
      expect(@recall.authorizer).to_not be_creatable_by(@user)
      expect(build(:recall).authorizer).to_not be_creatable_by(@user)
    end

    it 'allows reading' do
      expect(@recall.authorizer).to be_readable_by(@user)
    end

    it 'allows reading the collection' do
      expect(Recall.authorizer).to be_readable_by(@user)
    end

    it 'allows reading even if the user plan is cancelled' do
      expire_all!(@user)
      expect(@recall.authorizer).to be_readable_by(@user)
    end

    it 'disallows reading if the recall is published after the grace period expires' do
      expire_all!(@user)

      travel_to Time.now.end_of_grace_period + 1.minute do
        @recall.publication_date = Time.now
        @recall.save!
      end
      expect(@recall.authorizer).to_not be_readable_by(@user)
    end

    it 'disallows reading non-public feeds' do
      @nonpublic.each do |r|
        expect(r.authorizer).to_not be_readable_by(@user)
      end
    end

    it 'disallows updating' do
      expect(@recall.authorizer).to_not be_updatable_by(@user)
    end

    it 'disallows updating the collection' do
      expect(Recall.authorizer).to_not be_updatable_by(@user)
    end

    it 'disallows deletion' do
      expect(@recall.authorizer).to_not be_deletable_by(@user)
    end

  end

  context "for a Worker" do

    it 'allows creation' do
      expect(@recall.authorizer).to be_creatable_by(@worker)
      expect(build(:recall).authorizer).to be_creatable_by(@worker)
    end

    it 'allows reading' do
      expect(@recall.authorizer).to be_readable_by(@worker)
    end

    it 'allows reading the collection' do
      expect(Recall.authorizer).to be_readable_by(@worker)
    end

    it 'allows reading non-public feeds' do
      @nonpublic.each do |r|
        expect(r.authorizer).to be_readable_by(@worker)
      end
    end

    it 'allows reading the collection' do
      expect(RecallAuthorizer).to be_readable_by(@worker)
    end

    it 'allows updating' do
      expect(@recall.authorizer).to be_updatable_by(@worker)
    end

    it 'allows updating the collection' do
      expect(Recall.authorizer).to be_updatable_by(@worker)
    end

    it 'allows deletion' do
      expect(@recall.authorizer).to be_deletable_by(@worker)
    end

  end

end
