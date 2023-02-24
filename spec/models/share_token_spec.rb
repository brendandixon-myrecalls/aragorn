require 'rails_helper'

describe ShareToken, type: :model do

  context 'Validation' do

    before :example do
      @recall = create(:recall)
      ShareToken.for_recall(@recall).destroy_all
      @rl = build(:share_token, recall_id: @recall)
    end

    after :example do
      Recall.destroy_all
      ShareToken.destroy_all
    end

    it 'validates' do
      expect(@rl).to be_valid
    end

    it 'rejects a missing Recall identifier' do
      @rl.recall_id = nil
      expect(@rl).to be_invalid
      expect(@rl.errors).to have_key(:recall_id)
    end

    it 'rejects a duplicate link' do
      @rl.save!
      ra = build(:share_token, recall_id: @recall)
      expect(ra).to be_invalid
      expect(ra.errors).to have_key(:recall_id)
    end

    it 'accepts a Recall identifier' do
      ra = ShareToken.new(@recall.id)
      expect(ra).to be_valid
      expect(ra.recall_id).to eq(@recall.id)

      @rl.recall_id = @recall.id
      expect(@rl).to be_valid
      expect(@rl.recall_id).to eq(@recall.id)
    end

    it 'accepts and converts a Recall' do
      ra = ShareToken.new(@recall)
      expect(ra).to be_valid
      expect(ra.recall_id).to eq(@recall.id)

      @rl.recall_id = @recall
      expect(@rl).to be_valid
      expect(@rl.recall_id).to eq(@recall.id)
    end

    it 'rejects identifiers for non-existent Recalls' do
      @rl.recall_id = Recall.random_id
      expect(@rl).to be_invalid
      expect(@rl.errors).to have_key(:recall_id)
    end

  end

  context 'Behavior' do

    before :example do
      @recall = create(:recall)
      @rl = ShareToken.for_recall(@recall).first
    end

    after :example do
      ShareToken.destroy_all
      Recall.destroy_all
    end

    it 'increments the accessed count' do
      expected_count = @rl.access_count + 1

      @rl.accessed!
      expect(@rl.access_count).to eq(expected_count)

      @rl.reload
      expect(@rl.access_count).to eq(expected_count)
    end

    it 'returns the related Recall' do
      expect(@rl.recall).to eq(@recall)
    end

  end

  context 'Scope Behavior' do

    before :all do
      @recall = create(:recall)
      @rl = ShareToken.for_recall(@recall).first
    end

    after :all do
      ShareToken.destroy_all
      Recall.destroy_all
    end

    it 'returns the link for a given Recall' do
      rl = ShareToken.for_recall(@recall).first
      expect(rl).to eq(@rl)
    end

  end

end
