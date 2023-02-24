require 'rails_helper'

describe 'JsonWebToken', type: :lib do

  before :all do
    @id = BSON::ObjectId.new.to_s
  end

  it 'encodes and decodes a token' do
    token = JsonWebToken.encode(@id)
    id = JsonWebToken.decode(token)
    expect(id).to eq(@id)
  end

  it 'rejects expired tokens' do
    token = JsonWebToken.encode(@id, 1.day.ago)
    expect { JsonWebToken.decode(token) }.to raise_error(Authentication::AuthenticationError)
  end

  it 'rejects tokens with malformed User IDs' do
    token = JsonWebToken.encode('not a legal User id')
    expect { JsonWebToken.decode(token) }.to raise_error(Authentication::AuthenticationError)
  end

  it 'acknowledges a valid token' do
    token = JsonWebToken.encode(@id)
    expect(JsonWebToken.valid?(token, @id)).to be true
  end

  it 'invalidates expired tokens' do
    token = JsonWebToken.encode(@id, 1.day.ago)
    expect(JsonWebToken.valid?(token, @id)).to be false
  end

  it 'invalidates tokens with malformed User IDs' do
    id = 'not a legal User id'
    token = JsonWebToken.encode(id)
    expect(JsonWebToken.valid?(token, id)).to be false
  end

  it 'invalidates tokens with mismatched User IDs' do
    token = JsonWebToken.encode(@id)
    expect(JsonWebToken.valid?(token, BSON::ObjectId.new.to_s)).to be false
  end

end
