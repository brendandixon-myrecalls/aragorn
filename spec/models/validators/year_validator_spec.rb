require "rails_helper"

class YearModel < TestModelBase
  include Validations

  define_attribute :year1, Integer
  define_attribute :year2, Integer
  define_attribute :year3, Integer
  define_attribute :year4, Integer
  define_attribute :year5, Integer
  define_attribute :year6, Integer

  validates_is_year :year1, allow_blank: false

  # Allow blank validation
  validates_is_year :year2, allow_blank: true

  # Allow a minimum year
  validates_is_year :year3, minimum: 1942
  # Allow a minimum year as a lambda
  validates_is_year :year4, minimum: lambda{|r| 1942 }

  # Allow a maximum year
  validates_is_year :year5, maximum: 2001
  # Allow a maximum year as a lambda
  validates_is_year :year6, maximum: lambda{|r| 2001 }
end

describe Validations::YearValidator, type: :validator do

  before :example do
    @ym = YearModel.new
    @ym.year1 = 2000
    @ym.year2 = nil
    @ym.year3 = 1942
    @ym.year4 = 1942
    @ym.year5 = 2001
    @ym.year6 = 2001
  end

  it 'validates with valid items' do
    expect(@ym).to be_valid
  end

  it 'validates four digit integers' do
    @ym.year1 = 'notaninteger'
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year1)

    @ym.year1 = 123
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year1)

    @ym.year1 = 12345
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year1)
  end

  it 'disallows blank when requested' do
    @ym.year1 = nil
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year1)
  end

  it 'allows blank when requested' do
    @ym.year2 = nil
    expect(@ym).to be_valid
  end

  it 'validates the minimum year' do
    @ym.year3 = 1941
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year3)
  end

  it 'validates the minimum year via a lambda' do
    @ym.year4 = 1941
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year4)
  end

  it 'validates the maximum year' do
    @ym.year5 = 2002
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year5)
  end

  it 'validates the maximum year via a lambda' do
    @ym.year6 = 2002
    expect(@ym).to be_invalid
    expect(@ym.errors).to have_key(:year6)
  end

end
