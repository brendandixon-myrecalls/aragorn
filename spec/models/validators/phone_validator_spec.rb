require "rails_helper"

class PhoneModel < TestModelBase
  define_attribute :phone, :string
  define_attribute :phone_blank, :string

  validates_phone :phone
  validates_phone :phone_blank, allow_blank: true
end

describe 'Phone Validation', type: :validator do

  before :example do
    @pm = PhoneModel.new
    @pm.phone = '123.456.7890'
  end

  it 'rejects a malformed phone number' do
    @pm.phone = '12.34.56.78'
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:phone)
  end

  it 'does not require an phone if requested' do
    @pm.phone_blank = nil
    expect(@pm).to be_valid
    expect(@pm.errors).to_not have_key(:phone_blank)
  end

end
