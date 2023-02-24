module FeedConstants

  AFFECTED = [
    'children',
    'seniors'
  ]

  AUDIENCE = [
    'consumers',
    'professionals'
  ]
  DEFAULT_AUDIENCE = ['consumers']

  # See https://www.foodsafety.gov/poisoning/causes/allergens/index.html
  FOOD_ALLERGENS = [
    'dairy',
    'eggs',
    'fish',
    'shellfish',
    'nuts',
    'soy',
    'sulfites',
    'wheat'
  ]

  # See https://www.fda.gov/food/resourcesforyou/consumers/ucm103263.htm
  FOOD_CONTAMINANTS = [
    'e.coli',
    'foreign',
    'lead',
    'listeria',
    'salmonella',
    'other'
  ]

  PRODUCT_CONTAMINANTS = [
    'foreign',
    'lead',
    'other'
  ]

  ALL_CONTAMINANTS = FOOD_CONTAMINANTS + PRODUCT_CONTAMINANTS

  CPSC_CATEGORIES = [
    'animals',
    'commercial',
    'drugs',
    'electronics',
    'home',
    'outdoor',
    'personal',
    'toys',
  ]

  FDA_CATEGORIES = [
    'animals',
    'drugs',
    'food',
    'medical',
    'personal',
  ]

  MEDWATCH_CATEGORIES = [
    'drugs',
    'medical',
    'personal',
  ]

  USDA_CATEGORIES = [
    'food'
  ]

  NHTSA_CATEGORIES = [
    'home',
  ]

  NHTSA_TIRE_CATEGORIES = [
    'tires'
  ]

  NHTSA_VEHICLE_CATEGORIES = [
    'vehicles'
  ]

  def self.acts_as_vehicle?(categories = [])
    (categories & NHTSA_VEHICLE_CATEGORIES).length > 0
  end

  ACTS_AS_CONTAMINABLE_CATEGORIES = [
    'animals',
    'drugs',
    'food',
    'home',
    'medical',
    'personal',
    'toys'
  ]

  def self.acts_as_contaminable?(categories = [])
    ((categories || []) & ACTS_AS_CONTAMINABLE_CATEGORIES).length > 0
  end

  CAN_HAVE_ALLERGENS_CATEGORIES = [
    'animals',
    'drugs',
    'food',
    'personal',
  ]

  def self.can_have_allergens?(categories = [])
    ((categories || []) & CAN_HAVE_ALLERGENS_CATEGORIES).length > 0
  end

  CATEGORY_BUNDLES = {
    food: ['animals', 'food'],
    home: ['electronics', 'home', 'outdoor', 'personal', 'toys'],
    medical: ['drugs', 'medical'],
    commercial: ['commercial']
  }

  DEFAULT_CATEGORIES = (
    CATEGORY_BUNDLES[:food] +
    CATEGORY_BUNDLES[:home]
  ).uniq.sort

  PUBLIC_CATEGORIES = (
    CPSC_CATEGORIES +
    FDA_CATEGORIES +
    USDA_CATEGORIES +
    NHTSA_CATEGORIES
  ).uniq.sort

  ALL_CATEGORIES = (
    PUBLIC_CATEGORIES +
    MEDWATCH_CATEGORIES +
    NHTSA_TIRE_CATEGORIES +
    NHTSA_VEHICLE_CATEGORIES
  ).uniq.sort

  RISK = [
    'probable',
    'possible',
    'none'
  ]
  EMAILED_RISK = ['probable', 'possible']
  TEXTED_RISK  = ['probable']
  ALERTED_RISK = (EMAILED_RISK + TEXTED_RISK).uniq
  DEFAULT_RISK = ['probable', 'possible']

  NAMES = [
    'carseats',
    'cpsc',
    'fda',
    'medwatch',
    'tires',
    'usda',
    'vehicles'
  ]

  NONPUBLIC_NAMES = [
    'medwatch',
    'vehicles'
  ]

  PUBLIC_NAMES = NAMES - NONPUBLIC_NAMES

  SOURCES = [
    'cpsc',
    'fda',
    'medwatch',
    'usda',
    'nhtsa'
  ]

  NONPUBLIC_SOURCES = [
    'medwatch',
  ]

  PUBLIC_SOURCES = SOURCES - NONPUBLIC_SOURCES

  NAME_SOURCE = {
    'carseats' => 'nhtsa',
    'cpsc' => 'cpsc',
    'fda' => 'fda',
    'medwatch' => 'fda',
    'tires' => 'nhtsa',
    'usda' => 'usda',
    'vehicles' => 'nhtsa'
  }

  def self.source_for(name)
    NAME_SOURCE[name]
  end

  NAME_CATEGORIES = {
    'carseats': NHTSA_CATEGORIES,
    'cpsc': CPSC_CATEGORIES,
    'fda': FDA_CATEGORIES,
    'medwatch': MEDWATCH_CATEGORIES,
    'tires': NHTSA_TIRE_CATEGORIES,
    'usda': USDA_CATEGORIES,
    'vehicles': NHTSA_VEHICLE_CATEGORIES
  }.with_indifferent_access

  def self.categories_for(name)
    NAME_CATEGORIES[name] || []
  end

end
