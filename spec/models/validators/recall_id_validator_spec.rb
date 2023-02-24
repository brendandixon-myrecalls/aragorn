require "rails_helper"

class RecallIdModel < TestModelBase
  define_attribute :rid, :string
  define_attribute :rid_blank, :string

  validates_recall_id :rid
  validates_recall_id :rid_blank, allow_blank: true
end

describe 'Recall Id Validation', type: :validator do

  before :example do
    @ri = RecallIdModel.new
    @ri.rid = Recall.random_id
  end

  it 'accepts valid formats' do
    expect(@ri).to be_valid
  end

  it 'rejects an with illegal values' do
    Constants::SPECIAL.each do |c|
      @ri.rid = make_faux_id(c)
      expect(@ri).to be_invalid
      expect(@ri.errors).to have_key(:rid)
    end
  end

  it 'rejects too short values' do
    @ri.rid = make_faux_id('')
    expect(@ri).to be_invalid
    expect(@ri.errors).to have_key(:rid)
  end

  it 'rejects too long values' do
    @ri.rid = make_faux_id('AA')
    expect(@ri).to be_invalid
    expect(@ri.errors).to have_key(:rid)
  end

  it 'does not require an identifier if requested' do
    @ri.rid_blank = nil
    expect(@ri).to be_valid
    expect(@ri.errors).to_not have_key(:rid_blank)
  end

end
