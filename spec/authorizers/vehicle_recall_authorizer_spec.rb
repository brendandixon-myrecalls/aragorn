require 'rails_helper'

describe VehicleRecallAuthorizer, type: :authorizer do

  before :example do
    @admin = create(:admin)
    @worker = create(:worker)
    @recall = create(:vehicle_recall)
    @user = create(:user)
  end

  after :example do
    VehicleRecall.destroy_all
    User.destroy_all
  end

  context "for an Admin" do

    it 'allows creation' do
      expect(@recall.authorizer).to be_creatable_by(@admin)
      expect(build(:vehicle_recall).authorizer).to be_creatable_by(@admin)
    end

    it 'allows reading' do
      expect(@recall.authorizer).to be_readable_by(@admin)
    end

    it 'allows reading the collection' do
      expect(VehicleRecall.authorizer).to be_readable_by(@admin)
    end

    it 'allows reading the collection' do
      expect(VehicleRecallAuthorizer).to be_readable_by(@admin)
    end

    it 'allows updating' do
      expect(@recall.authorizer).to be_updatable_by(@admin)
    end

    it 'allows updating the collection' do
      expect(VehicleRecall.authorizer).to be_updatable_by(@admin)
    end

    it 'allows deletion' do
      expect(@recall.authorizer).to be_deletable_by(@admin)
    end

  end

  context "for a User" do

    it 'disallows creation' do
      expect(@recall.authorizer).to_not be_creatable_by(@user)
      expect(build(:vehicle_recall).authorizer).to_not be_creatable_by(@user)
    end

    it 'disallows reading' do
      expect(@recall.authorizer).to_not be_readable_by(@user)
    end

    it 'disallows reading the collection' do
      expect(VehicleRecall.authorizer).to_not be_readable_by(@user)
    end

    it 'disallows reading the collection' do
      expect(VehicleRecallAuthorizer).to_not be_readable_by(@user)
    end

    it 'disallows updating' do
      expect(@recall.authorizer).to_not be_updatable_by(@user)
    end

    it 'disallows updating the collection' do
      expect(VehicleRecall.authorizer).to_not be_updatable_by(@user)
    end

    it 'disallows deletion' do
      expect(@recall.authorizer).to_not be_deletable_by(@user)
    end

  end

  context "for a Worker" do

    it 'allows creation' do
      expect(@recall.authorizer).to be_creatable_by(@worker)
      expect(build(:vehicle_recall).authorizer).to be_creatable_by(@worker)
    end

    it 'allows reading' do
      expect(@recall.authorizer).to be_readable_by(@worker)
    end

    it 'allows reading the collection' do
      expect(VehicleRecall.authorizer).to be_readable_by(@worker)
    end

    it 'allows updating' do
      expect(@recall.authorizer).to be_updatable_by(@worker)
    end

    it 'allows updating the collection' do
      expect(VehicleRecall.authorizer).to be_updatable_by(@worker)
    end

    it 'allows deletion' do
      expect(@recall.authorizer).to be_deletable_by(@worker)
    end

  end

end
