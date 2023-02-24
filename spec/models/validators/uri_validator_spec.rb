require "rails_helper"

class UriModel < TestModelBase
  include Validations

  define_attribute :uri1, URI
  define_attribute :uri2, URI
  define_attribute :uri3, URI
  define_attribute :uri4, URI

  validates_is_uri :uri1
  # Allow blank validation
  validates_is_uri :uri2, allow_blank: true
  # Allow a single scheme
  validates_is_uri :uri3, schemes: :ftp
  # Allow multiple schemes, possibly custom
  validates_is_uri :uri4, schemes: [:ftp, :magic]
end

describe Validations::UriValidator, type: :validator do

  before :example do
    @um = UriModel.new
    @um.uri1 = 'https://google.com/'
    @um.uri3 = 'ftp://something.com/file'
    @um.uri4 = 'magic://funky/time/uri'
  end

  it 'validates with valid items' do
    expect(@um).to be_valid
  end

  it 'validates the illegal schemes' do
    @um.uri1 = 'ftp://something.com/file'
    expect(@um).to be_invalid
    expect(@um.errors).to have_key(:uri1)
  end

  it 'allows blank when requested' do
    @um.uri2 = ''
    expect(@um).to be_valid

    @um.uri2 = nil
    expect(@um).to be_valid
  end

  it 'disallows blank when requested' do
    @um.uri1 = ''
    expect(@um).to be_invalid
    expect(@um.errors).to have_key(:uri1)

    @um.uri1 = nil
    expect(@um).to be_invalid
    expect(@um.errors).to have_key(:uri1)
  end

end
