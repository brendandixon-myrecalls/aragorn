require "rails_helper"

class UniquenessModel < TestModelBase
  include ActiveModel::Callbacks
  include Mongoid::Document
  include Fields
  include Validations

  define_fields [
    { field: :em, as: :email, type: String, default: '' },
    { field: :f1, as: :field1, type: String, default: '' },
    { field: :f2, as: :field2, type: String, default: '' }
  ]

  validates_uniqueness_of :email, allow_blank: true
  validates_uniqueness_of :field1, scope: :field2, allow_blank: true
end

describe Validations::UniquenessValidator, type: :validator do

  before :example do
    @em = UniquenessModel.new(email: 'bob.jones@nomail.com')
    @f1 = UniquenessModel.new(email: 'f1@nomail.com', field1: 'field11', field2: 'field12')
    @f2 = UniquenessModel.new(email: 'f2@nomail.com', field1: 'field21', field2: 'field22')
  end

  after :example do
    UniquenessModel.destroy_all
  end

  it 'allows unique values' do
    expect(@em).to be_valid
  end

  it 'disallows duplicate values' do
    em = UniquenessModel.new(email: 'bob.jones@nomail.com')
    em.save!

    expect(@em).to be_invalid
    expect(@em.errors).to have_key(:email)
  end

  it 'does not require a value if requested' do
    @em.email = nil
    expect(@em).to be_valid
    expect(@em.errors).to_not have_key(:email)
  end

  it 'limits uniqueness to a supplied scope' do
    expect(@f1).to be_valid
    expect(@f2).to be_valid

    @f1.save!
    @f2.save!

    @f2.field1 = @f1.field1
    expect(@f2).to be_valid

    @f2.field2 = @f1.field2
    expect(@f2).to_not be_valid
    expect(@f2.errors).to have_key(:field1)
  end

end
