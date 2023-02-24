require 'rails_helper'

class TestModel < TestModelBase
  class<<self
    def path_for
      'tests'
    end
  end
end

TEST_MULTIPLE = {
  jsonapi: { version: '1.0' },
  data: [
    { type: 'tests', id: 42, attributes: { foo: 100 }},
    { type: 'tests', id: 43, attributes: { foo: 101 }},
  ]
}

TEST_MULTIPLE_INCLUDED = {
  jsonapi: { version: '1.0' },
  data: [
    { type: 'tests', id: 42, attributes: { foo: 100 }},
    { type: 'tests', id: 43, attributes: { foo: 101 }},
  ],
  included: [
    { type: 'related', id: 24, attributes: { bar: 200 }}
  ]
}

TEST_SINGLE = {
  jsonapi: { version: '1.0' },
  data: {
    type: 'tests',
    id: 42,
    attributes: { foo: 100 },
    links: { self: 'http://test.org:8080/tests/42' }
  }
}

TEST_SINGLE_INCLUDED = {
  jsonapi: { version: '1.0' },
  data: {
    type: 'tests',
    id: 42,
    attributes: { foo: 100 },
    links: { self: 'http://test.org:8080/tests/42' }
  },
  included: [
    { type: 'related', id: 24, attributes: { bar: 200 }}
  ]
}

TEST_SINGLE_NO_SELF = {
  jsonapi: { version: '1.0' },
  data: {
    type: 'tests',
    id: 42,
    attributes: { foo: 100 }
  }
}

TEST_ERRORS = [
  { status: 42, title: 'Something bad happended' },
  { status: 43, title: 'Another bad thing', detail: 'But with detail' }
]

describe JsonEnvelope, type: :lib do

  it 'generates JSON for a single object' do
    je = JsonEnvelope.new(TestModel)
    je.add_datum(42, { foo: 100 })
    expect(je.as_json).to eq(TEST_SINGLE)
  end

  it 'generates JSON for a single object with included objects' do
    je = JsonEnvelope.new(TestModel)
    je.add_datum(42, { foo: 100 })
    je.add_related({ type: 'related', id: 24, attributes: { bar: 200 }})
    expect(je.as_json).to eq(TEST_SINGLE_INCLUDED)
  end

  it 'generates JSON for a single object without the self link' do
    je = JsonEnvelope.new(TestModel)
    je.add_datum(42, { foo: 100 })
    expect(je.as_json(exclude_self_link: true)).to eq(TEST_SINGLE_NO_SELF)
  end

  it 'generates flat (non-JSON-API) JSON for a single object if requested' do
    je = JsonEnvelope.new(TestModel)
    je.add_datum(42, { foo: 100 })
    expect(je.as_json(flat: true)).to eq({id: 42, foo: 100})
  end

  it 'generates JSON for multiple objects' do
    je = JsonEnvelope.new(TestModel)
    je.add_datum(42, { foo: 100 })
    je.add_datum(43, { foo: 101 })
    expect(je.as_json).to eq(TEST_MULTIPLE)
    expect(je).to be_is_collection
  end

  it 'generates JSON for multiple objects with included objects' do
    je = JsonEnvelope.new(TestModel)
    je.add_datum(42, { foo: 100 })
    je.add_datum(43, { foo: 101 })
    je.add_related([{ type: 'related', id: 24, attributes: { bar: 200 }}])
    expect(je.as_json).to eq(TEST_MULTIPLE_INCLUDED)
    expect(je).to be_is_collection
  end

  it 'parses JSON' do
    je = JsonEnvelope.from_json('tests', TEST_MULTIPLE.to_json)
    i = 42
    f = 100
    je.each_datum do |id, attributes|
      expect(id).to eq(i)
      expect(attributes[:foo]).to eq(f)

      i += 1
      f += 1
    end
  end

  it 'collects errors' do
    je = JsonEnvelope.new(TestModel)
    TEST_ERRORS.each do |error|
      je.add_error(error[:status], error[:title], error[:detail])
    end

    i = 0
    je.each_error do |s, t, d|
      error = TEST_ERRORS[i]
      expect(s).to eq(error[:status])
      expect(t).to eq(error[:title])
      expect(d).to eq(error[:detail])
      i += 1
    end
  end

  it 'renders pagination data' do
    je = JsonEnvelope.new(TestModel)
    (0...5).each{|i| je.add_datum(42+i, foo: 100+i)}
    je.add_pagination(offset: 0, limit: 5, total: 30, dummy1: 'foo', dummy2: 'bar,baz')

    j = je.as_json.deep_symbolize_keys
    expect(j[:data]).to eq([
      { type: 'tests', id: 42, attributes: { foo: 100 } },
      { type: 'tests', id: 43, attributes: { foo: 101 } },
      { type: 'tests', id: 44, attributes: { foo: 102 } },
      { type: 'tests', id: 45, attributes: { foo: 103 } },
      { type: 'tests', id: 46, attributes: { foo: 104 } },
    ])

    expect(j[:links]).to eq({
      self: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      first: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      prev: nil,
      next: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=5',
      last: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=25',
    })

    expect(j[:meta]).to eq({total: 30})
  end

  it 'includes the previous link if the offset is greater than zero' do
    je = JsonEnvelope.new(TestModel)
    (0...5).each{|i| je.add_datum(42+i, foo: 100+i)}
    je.add_pagination(offset: 5, limit: 5, total: 30, dummy1: 'foo', dummy2: 'bar,baz')

    j = je.as_json.deep_symbolize_keys
    expect(j[:links]).to eq({
      self: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=5',
      first: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      prev: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      next: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=10',
      last: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=25',
    })
  end

  it 'excludes the previous link if the offset is equal to zero' do
    je = JsonEnvelope.new(TestModel)
    (0...5).each{|i| je.add_datum(42+i, foo: 100+i)}
    je.add_pagination(offset: 0, limit: 5, total: 30, dummy1: 'foo', dummy2: 'bar,baz')

    j = je.as_json.deep_symbolize_keys
    expect(j[:links]).to eq({
      self: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      first: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      prev: nil,
      next: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=5',
      last: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=25',
    })
  end

  it 'excludes the previous link if the offset is less than zero' do
    je = JsonEnvelope.new(TestModel)
    (0...5).each{|i| je.add_datum(42+i, foo: 100+i)}
    je.add_pagination(offset: -5, limit: 5, total: 30, dummy1: 'foo', dummy2: 'bar,baz')

    j = je.as_json.deep_symbolize_keys
    expect(j[:links]).to eq({
      self: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      first: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      prev: nil,
      next: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=5',
      last: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=25',
    })
  end

  it 'includes the next link if more items exist' do
    je = JsonEnvelope.new(TestModel)
    (0...5).each{|i| je.add_datum(42+i, foo: 100+i)}
    je.add_pagination(offset: 5, limit: 5, total: 30, dummy1: 'foo', dummy2: 'bar,baz')

    j = je.as_json.deep_symbolize_keys
    expect(j[:links]).to eq({
      self: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=5',
      first: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      prev: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      next: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=10',
      last: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=25',
    })
  end

  it 'excludes the next link if no more items exist' do
    je = JsonEnvelope.new(TestModel)
    (0...5).each{|i| je.add_datum(42+i, foo: 100+i)}
    je.add_pagination(offset: 25, limit: 5, total: 30, dummy1: 'foo', dummy2: 'bar,baz')

    j = je.as_json.deep_symbolize_keys
    expect(j[:links]).to eq({
      self: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=25',
      first: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=0',
      prev: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=20',
      next: nil,
      last: 'http://test.org:8080/tests?dummy1=foo&dummy2=bar%2Cbaz&limit=5&offset=25',
    })
  end

  it 'does not render page links or query parameters for parented collections' do
    je = JsonEnvelope.new(TestModel)
    u = build(:user)
    je.add_parent(u)

    (0...5).each{|i| je.add_datum(42+i, foo: 100+i)}
    je.add_pagination(offset: 0, limit: 5, total: 30, dummy1: 'foo', dummy2: 'bar,baz')

    j = je.as_json.deep_symbolize_keys
    expect(j[:data]).to eq([
      { type: 'tests', id: 42, attributes: { foo: 100 } },
      { type: 'tests', id: 43, attributes: { foo: 101 } },
      { type: 'tests', id: 44, attributes: { foo: 102 } },
      { type: 'tests', id: 45, attributes: { foo: 103 } },
      { type: 'tests', id: 46, attributes: { foo: 104 } },
    ])

    expect(j[:links]).to eq({
      self: "http://test.org:8080/users/#{u.id}/tests",
    })

    expect(j[:meta]).to eq({total: 30})
  end

  it 'renders only errors if both errors and data are present' do
    je = JsonEnvelope.new(TestModel)
    je.add_datum(42, foo: 100)
    je.add_pagination(offset: 0, limit: 5, total: 30)
    je.add_error(500, 'Server Error')

    j = je.as_json.deep_symbolize_keys
    expect(j[:data]).to be_nil
    expect(j[:links]).to be_nil
    expect(j[:meta]).to be_nil
    expect(j[:errors]).to be_present
    expect(j[:errors].length).to eq(1)
    expect(j[:errors].first).to eq({ status: 500, title: 'Server Error'})
  end

end
