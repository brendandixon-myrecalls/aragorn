module USRegions

  STATES = [
    'AL', 'AK', 'AZ', 'AR',
    'CA', 'CO', 'CT',
    'DE', 'DC',
    'FL',
    'GA',
    'HI',
    'ID', 'IL', 'IN', 'IA',
    'KS', 'KY',
    'LA',
    'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT',
    'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND',
    'OH', 'OK', 'OR',
    'PA',
    'RI',
    'SC', 'SD',
    'TN', 'TX',
    'UT',
    'VT', 'VA',
    'WA', 'WV', 'WI', 'WY'
  ]

  TERRITORIES = [ 'TT' ]

  ALL_STATES = STATES + TERRITORIES

  COASTS = {
    east: ['ME', 'VT', 'NH', 'MA', 'RI', 'CT', 'NJ', 'DE', 'DC', 'VA', 'NC', 'SC', 'GA', 'FL', 'NY', 'PA'],
    west: ['WA', 'OR', 'CA']
  }

  REGIONS = {
    west: ['WA', 'OR', 'CA', 'NV', 'ID', 'MT', 'WY', 'UT', 'CO', 'AK', 'HI'],
    southwest: ['AZ', 'NM', 'TX', 'OK'],
    midwest: ['ND', 'SD', 'NE', 'KS', 'MN', 'IA', 'MO', 'WI', 'IL', 'IN', 'OH', 'MI'],
    southeast: ['AR', 'LA', 'MS', 'AL', 'GA', 'FL', 'TN', 'KY', 'WV', 'VA', 'NC', 'SC'],
    northeast: ['NY', 'PA', 'MD', 'VT', 'ME', 'NH', 'MA', 'RI', 'CT', 'NJ', 'DE', 'DC'],
    nationwide: STATES
  }

end
