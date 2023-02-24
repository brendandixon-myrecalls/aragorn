require "rails_helper"

class VinModel < TestModelBase
  include Validations

  define_attribute :vin1, String
  define_attribute :vin2, String

  validates_is_vin :vin1, allow_blank: false
  validates_is_vin :vin2, allow_blank: true
end

describe Validations::YearValidator, type: :validator do

  before :example do
    @vm = VinModel.new
    @vm.vin1 = 'JTDKARFU0H3528314'
    @vm.vin2 = nil
  end

  it 'validates with valid items' do
    expect(@vm).to be_valid
  end

  it 'validates the VIN length' do
    vin = @vm.vin1

    @vm.vin1 = vin[0,vin.length-1]
    expect(@vm).to be_invalid
    expect(@vm.errors).to have_key(:base)

    @vm.vin1 = vin + '1'
    expect(@vm).to be_invalid
    expect(@vm.errors).to have_key(:base)
  end

  it 'disallows blank when requested' do
    @vm.vin1 = nil
    expect(@vm).to be_invalid
    expect(@vm.errors).to have_key(:base)
  end

  it 'allows blank when requested' do
    @vm.vin2 = nil
    expect(@vm).to be_valid
  end

  it 'rejects malformed VINs' do
    @vm.vin1 = '12345678901234567'
    expect(@vm).to be_invalid
    expect(@vm.errors).to have_key(:base)
  end

end
