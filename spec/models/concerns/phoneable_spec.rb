require 'rails_helper'

class PhoneableModel < TestModelBase
  include Phoneable

  define_attribute :phone, :string
  define_attribute :street_seconday, :string
  define_attribute :city, :string
  define_attribute :state, :string
  define_attribute :country, :string
  define_attribute :postal_code, :string
end

describe Phoneable, type: :concern do

  before :example do
    PhoneableModel.exists = false
    @phone = PhoneableModel.new
  end

  it 'does not require a phone number' do
    @phone.phone = ''
    expect(@phone).to be_valid

    @phone.phone = nil
    expect(@phone).to be_valid
  end

  it 'accepts and normalizes valid phone numbers' do
    [
      '1235551212',
      '123 5551212',
      '123 555 1212',
      '123.555.1212',
      '123-555-1212',
      '123.555-1212',
      '123-555.1212',
      '123 555.1212',
      '123 555-1212',
      '123.555 1212',
      '123-555 1212',
      '123.5551212',
      '123-5551212',
      '(123)555-1212',
      '(123)555.1212',
      '(123) 555-1212',
      '(123) 555.1212',
      '(123)5551212',
      '(123)555 1212',
      '(123) 555 1212'
    ].each do |n|
      @phone.phone = n
      expect(@phone).to be_valid
      expect(@phone.errors).to_not have_key(:phone)
      expect(@phone.phone).to eq('123.555.1212')
    end
  end

  it 'rejects malformed phone numbers' do
    [
      'abcde',
      '111111111111111111111111111',
      'abc123efg456',
      '123-456-789-123'
    ].each do |n|
      @phone.phone = n
      expect(@phone).to be_invalid
      expect(@phone.errors).to have_key(:phone)
    end
  end

end
