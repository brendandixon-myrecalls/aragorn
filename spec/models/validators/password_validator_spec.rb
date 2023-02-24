require "rails_helper"

class PasswordModel < TestModelBase
  define_attribute :password, :string
  define_attribute :password_blank, :string

  validates_password :password
  validates_password :password_blank, allow_blank: true
end

describe 'Password Validation', type: :validator do

  before :all do
    @lower = Constants::LOWERCASE
    @upper = Constants::UPPERCASE
    @digits = Constants::DIGITS
    @special = Constants::SPECIAL
    @length = 16
  end

  before :example do
    @pm = PasswordModel.new
  end

  it 'requires an password' do
    @pm.password = nil
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:password)
  end

  it 'rejects an invalid password' do
    @pm.password = "weak"
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:password)
  end

  it 'accepts a valid password' do
    @pm.password = "bob42Jones@nomail.com"
    expect(@pm).to be_valid
    expect(@pm.errors).to_not have_key(:password)
  end

  it 'requires at least one lower-case letter' do
    p = make_password(@upper, @digits, @special)
    @pm.password = p + @upper.first
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:password)

    @lower.each do |c|
      @pm.password = p + c
      expect(@pm).to be_valid
    end
  end

  it 'requires at least one upper-case letter' do
    p = make_password(@lower, @digits, @special)
    @pm.password = p + @lower.first
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:password)

    @upper.each do |c|
      @pm.password = p + c
      expect(@pm).to be_valid
    end
  end

  it 'requires at least one digit' do
    p = make_password(@lower, @upper, @special)
    @pm.password = p + @lower.first
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:password)

    @digits.each do |c|
      @pm.password = p + c
      expect(@pm).to be_valid
    end
  end

  it 'requires at least one special character' do
    p = make_password(@lower, @upper, @digits)
    @pm.password = p + @lower.first
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:password)

    @special.each do |c|
      @pm.password = p + c
      expect(@pm).to be_valid
    end
  end

  it 'requires a minimum number of characters' do
    p = make_password(@lower, @upper, @digits)
    expect(p.length+1).to eq(@length)

    @pm.password = p
    expect(@pm).to be_invalid
    expect(@pm.errors).to have_key(:password)

    @pm.password = p + @special.first
    expect(@pm).to be_valid
  end

  # NOTE: Enable this if the RegEx can be used to check maximum length
  # it 'cannot exceed a maximum number of characters' do
  #   p = make_password(@lower, @upper, @digits)
  #   p = p + (@special.first * (ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED-p.length+1))
  #   expect(p.length-1).to eq(ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED)

  #   @pm.password = p
  #   expect(@pm).to be_invalid
  #   expect(@pm.errors).to have_key(:password)

  #   @pm.password = p.slice(0, ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED)
  #   expect(@pm).to be_valid
  # end

  it 'does not require an password if requested' do
    @pm.password = "bob42Jones@nomail.com"
    @pm.password_blank = nil
    expect(@pm).to be_valid
    expect(@pm.errors).to_not have_key(:password_blank)
  end

  def make_password(s1, s2, s3)
    (0...5).inject([]){|a, i| a << s1[Helper.rand(s1.length)]; a}.join +
    (0...5).inject([]){|a, i| a << s2[Helper.rand(s2.length)]; a}.join +
    (0...5).inject([]){|a, i| a << s3[Helper.rand(s3.length)]; a}.join
  end

end
