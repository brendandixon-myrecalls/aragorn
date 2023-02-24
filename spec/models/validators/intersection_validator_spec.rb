require "rails_helper"

VALID_ITEMS = %w(a b c d)

class IntersectionModel < TestModelBase
  include Validations

  define_attribute :list, Array

  define_attribute :list1, Array
  define_attribute :list2, Array
  define_attribute :list3, Array
  define_attribute :list4, Array

  validates_intersection_of :list1, in: VALID_ITEMS
  validates_intersection_of :list2, in: VALID_ITEMS, allow_blank: true
  validates_intersection_of :list3, in: lambda{|im| im.list }, allow_blank: true
  validates_intersection_of :list4, in: []
end

describe Validations::IntersectionValidator, type: :validator do

  before :example do
    @im = IntersectionModel.new(list: %w(a b c), list1: VALID_ITEMS.dup)
  end

  it 'validates with valid items' do
    expect(@im).to be_valid

    @im.list2 = VALID_ITEMS.dup
    expect(@im).to be_valid
  end

  it 'rejects items outside the list' do
    @im.list1 << 'unknown'
    expect(@im).to be_invalid
  end

  it 'disallows empty lists unless requested' do
    @im.list1 = []
    expect(@im).to be_invalid
  end

  it 'allows empty lists when requested' do
    @im.list2 = []
    expect(@im).to be_valid
  end

  it 'disallows non-array values' do
    @im.list1 = 'a'
    expect(@im).to be_invalid
  end

  it 'accepts Procs for the validation list' do
    @im.list3 = [@im.list.first, @im.list.last]
    expect(@im).to be_valid
  end

  it 'disallows items when there are no legal values' do
    @im.list4 = ['unexpected']
    expect(@im).to be_invalid
  end

end
