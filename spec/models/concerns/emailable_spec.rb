require 'rails_helper'

class EmailableModel < TestModelBase
  include Emailable

  define_attribute :email, :string
end

describe Emailable, type: :concern do

  before :example do
    EmailableModel.exists = false
    @email = EmailableModel.new
  end

  it 'requires an email' do
    @email.email = nil
    expect(@email).to be_invalid
    expect(@email.errors).to have_key(:email)
  end

  it 'requires a unique email' do
    EmailableModel.exists = true
    expect(@email).to be_invalid
    expect(@email.errors).to have_key(:email)
  end

  it 'rejects malformed email addresses' do
    @email.email = "notan@emailaddress"
    expect(@email).to be_invalid
    expect(@email.errors).to have_key(:email)
  end

  it 'rejects too short addresses' do
    @email.email = "a@b.c"
    expect(@email).to be_invalid
    expect(@email.errors).to have_key(:email)
  end

  it 'rejects too long addresses' do
    @email.email = ('x' * 255) + "@foo.com"
    expect(@email).to be_invalid
    expect(@email.errors).to have_key(:email)
  end

end
