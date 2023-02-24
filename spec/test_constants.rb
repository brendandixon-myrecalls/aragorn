module TestConstants

  # NHTSA campaign identifiers
  CAMPAIGNS = [
    '13V014000',
    '13V123000',
    '14V148000',
    '16V741000',
    '16V747000',
    '17V119000',
    '17V295000',
    '18V403000',
    '18V561000',
    '18V566000',
    '18V572000',
    '18V571000',
    '18V581000',
    '18V570000',
    '18V582000',
    '18V583000',
    '18V587000',
    '18V584000',
    '18V589000',
    '18V591000',
    '18V588000',
    '18V579000',
    '18V593000',
    '18V595000',
    '18V600000',
    '18V601000',
    '18V596000',
    '18V597000',
    '18V594000',
    '18V598000'
  ]

  REGIONS = [
    :northeast,
    :west,
    :southeast,
    :midwest,
    :northeast,
    :west,
    :southwest,
    :northeast,
    :southeast,
    :west,
    :midwest,
    :southwest,
    :southeast,
    :northeast,
  ].cycle

  # Generated at https://vingenerator.org
  VEHICLES = {
    '1GNDT13W5R2133070' => {make: 'Chevrolet', model: 'S 10 Blazer', year: 1994},
    'JH4DB7650SS002893' => {make: 'Acura', model: 'Integra', year: 1995},
    'WBAAV33421FU91768' => {make: 'BMW', model: '3-SERIES', year: 2001},
    'WDCGG8HB0AF462890' => {make: 'Mercedes Benz', model: 'GLK Class', year: 2010},
    '1HGCM66554A033052' => {make: 'Honda', model: 'Accord', year: 2004},
    'WDDHF8JB4DA682581' => {make: 'Mercedex Benz', model: 'E', year: 2013},
    'JH4DB1540NS801082' => {make: 'Acura', model: 'Integra', year: 1992},
    'JH4DB1670LS801802' => {make: 'Acura', model: 'Integra', year: 1990},
    '5TFHW5F13AX136128' => {make: 'Toyota', model: 'Tundra', year: 2010},
    '1GNDT13W3W2249640' => {make: 'Chevrolet', model: 'Blazer', year: 1998},

    '1D4HR48N73F526307' => {make: 'Dodge', model: 'Durango', year: 2003},
    'JNRAS08W64X222014' => {make: 'Infiniti', model: 'FX35', year: 2004},
    'JH4DB1642PS001515' => {make: 'Acura', model: 'Integra', year: 1993},
    '3GCRKSE34AG162050' => {make: 'Chevrolet', model: 'Silverado 1500', year: 2010},
    '1B4HS28N51F547639' => {make: 'Dodge', model: 'Durango', year: 2001},
    'JH4KA3161HC006800' => {make: 'Acura', model: 'Legend', year: 1987},
    '1GKEV16K8LF538649' => {make: 'GMC', model: 'Suburban', year: 1990},
    'YV1AH852071023377' => {make: 'Volvo', model: 'S80', year: 2007},
    'JH4DA3340GS007428' => {make: 'Acura', model: 'Integra', year: 1986},
    '3VWSD29M11M069435' => {make: 'Volkswagen', model: 'Jetta', year: 2001},

    '1J4FT68SXXL633294' => {make: 'Jeep', model: 'Cherokee', year: 1999},
    '1FMZK04185GA30815' => {make: 'Ford', model: 'Freestyle', year: 2005},
    '1MEBM62F2JH693379' => {make: 'Mercury', model: 'Cougar', year: 1988},
    '1G4AW69N2DH524774' => {make: 'Buick', model: 'Electra', year: 1983},
    '2FAFP73W1WX172908' => {make: 'Ford', model: 'Crown Victoria', year: 1998},
    '1FTPX14524NB00101' => {make: 'Ford', model: 'F 150', year: 2004},
    '1FAFP55U91A180689' => {make: 'Ford', model: 'Taurus', year: 2001},
    'JKBVNKD167A013982' => {make: 'Kawasaki', model: 'Vn 1600', year: 2007},
    'SMT905RN59T379271' => {make: 'Triumph', model: 'America', year: 2009},
    'KNDPBCA25B7076883' => {make: 'KIA', model: 'Sportage', year: 2011},

    '1A8HW58268F133559' => {make: 'Chrysler', model: 'Aspen', year: 2008},
    '5FNRL18613B046732' => {make: 'Honda', model: 'Odyssey', year: 2003},
    '1HD1BX510BB027648' => {make: 'Harley Davidson', model: 'Fat Boy', year: 2011},
    'JHLRE48518C002529' => {make: 'Honda', model: 'CR V', year: 2008},
    'YS3DD78N4X7055320' => {make: 'Saab', model: '9 3', year: 1999},
    'WBSPM9C52BE202514' => {make: 'BMW', model: 'M3', year: 2011},
    '1HGCG1657WA051534' => {make: 'Honda', model: 'Accord', year: 1998},
    '3FAFP13P41R199033' => {make: 'Ford', model: 'Escort', year: 2001},
    '2C3CCAET4CH256062' => {make: 'Chrysler', model: '300C', year: 2012},
    '2T3DK4DV8CW082696' => {make: 'Toyota', model: 'Rav4', year: 2012},
  }

  VINS = VEHICLES.keys

  # These vkeys do not intersect with any listed VEHICLES
  UNKNOWN_VKEYS = [
    'yugo|55|1980',
    'yugo|tempo|1982',
    'yugo|gv|1993',
    'ferrari|812 gts|2018',
    'ferrari|sf90|2017',
    'ferrari|f8 tributo|2017'
  ]

end
