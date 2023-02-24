require 'rails_helper'

describe 'Vehicles', type: :lib do

  describe 'VIN Validation' do

    it 'accepts as valid well-formed VINs' do
      TestConstants::VINS.each do |vin|
        expect(Vehicles.valid_vin?(vin)).to be true
      end
    end

    it 'rejects VINs that are too short' do
      TestConstants::VINS.each do |vin|
        expect(Vehicles.valid_vin?(vin[0, 16])).to be false
      end
    end

    it 'rejects invalid VINs' do
      vin = select_vin
      vin.length.times do |i|
        v = (vin[0, i] || '') + '0' + (vin[i, vin.length] || '')
        expect(Vehicles.valid_vin?(v)).to be false
      end
    end

  end

  describe 'VKey Management' do

    it 'accepts valid Vkeys' do
      expect(Vehicles.valid_vkey?('BMW|3SERIES|2018')).to be true
    end

    it 'accepts whitespace in the make name of valid Vkeys' do
      expect(Vehicles.valid_vkey?('Mercedes Benz|3SERIES|2018')).to be true
    end

    it 'accepts dashes in the make name of valid Vkeys' do
      expect(Vehicles.valid_vkey?('Mercedes-Benz|3SERIES|2018')).to be true
    end

    it 'accepts digits in the make name of valid Vkeys' do
      expect(Vehicles.valid_vkey?('BMW42|3-SERIES|2018')).to be true
    end

    it 'rejects VKeys with newlines in the make name' do
      expect(Vehicles.valid_vkey?("Mercedes\nBenz|3SERIES|2018")).to be true
    end

    it 'accepts whitespace in the model of valid Vkeys' do
      expect(Vehicles.valid_vkey?('BMW|3 SERIES|2018')).to be true
    end

    it 'accepts dashes in the model of valid Vkeys' do
      expect(Vehicles.valid_vkey?('BMW|3-SERIES|2018')).to be true
    end

    it 'accepts digits in the model of valid Vkeys' do
      expect(Vehicles.valid_vkey?('BMW|3-SERIES|2018')).to be true
    end

    it 'accepts any 4-digit for the year valid Vkeys' do
      (1940..Time.now.year).each do |year|
        expect(Vehicles.valid_vkey?("BMW|3-SERIES|#{year}")).to be true
      end
    end

    it 'rejects VKeys with years less than 4-digits' do
      (1940..Time.now.year).each do |year|
        expect(Vehicles.valid_vkey?("BMW|3-SERIES|#{year / 10}")).to be false
      end
    end

    it 'rejects VKeys with years containing non-digit characters' do
      expect(Vehicles.valid_vkey?('BMW|3-SERIES|2018')).to be true
      expect(Vehicles.valid_vkey?('BMW|3-SERIES|a018')).to be false
      expect(Vehicles.valid_vkey?('BMW|3-SERIES|2a18')).to be false
      expect(Vehicles.valid_vkey?('BMW|3-SERIES|20a8')).to be false
      expect(Vehicles.valid_vkey?('BMW|3-SERIES|201a')).to be false
    end

    it 'converts a Vehicle hash into a valid VKey' do
      [
        { make: 'BMW', model: '3-SERIES', year: 2018 },
        { make: 'BMW', model: '3-SERIES', year: '2018' },
        { make: 'TOYOTA', model: 'LAND ROVER', year: 2018 },
        { make: 'TOYOTA', model: 'LAND ROVER', year: '2018' },
        { make: 'MERCEDES BENZ', model: 'C500', year: 2018 },
        { make: 'MERCEDES BENZ', model: 'C500', year: '2018' },
      ].each do |v|
        vkey = Vehicles.generate_vkey(v[:make], v[:model], v[:year])
        expect(Vehicles.valid_vkey?(vkey)).to be true
        expect(vkey).to eq("#{v[:make]}|#{v[:model]}|#{v[:year]}".downcase)
      end
    end

    it 'ignores unknown keys when converting a Vehicle hash into a valid VKey' do
      [
        { make: 'BMW', model: '3-SERIES', year: 2018, notused: 'notused' },
        { make: 'BMW', model: '3-SERIES', year: '2018', notused: 'notused' },
        { make: 'TOYOTA', model: 'LAND ROVER', year: 2018, notused: 'notused' },
        { make: 'TOYOTA', model: 'LAND ROVER', year: '2018', notused: 'notused' },
        { make: 'MERCEDES BENZ', model: 'C500', year: 2018, notused: 'notused' },
        { make: 'MERCEDES BENZ', model: 'C500', year: '2018', notused: 'notused' },
      ].each do |v|
        vkey = Vehicles.generate_vkey(v[:make], v[:model], v[:year])
        expect(Vehicles.valid_vkey?(vkey)).to be true
        expect(vkey).to eq("#{v[:make]}|#{v[:model]}|#{v[:year]}".downcase)
      end
    end

    it 'strips extra whitespace from the Vehicle hash values before creating a valid VKey' do
      [
        { make: '    BMW         ', model: '     3-SERIES           ', year: 2018 },
        { make: '    BMW         ', model: '     3-SERIES           ', year: '      2018            ' },
        { make: '    TOYOTA        ', model: '   LAND ROVER  ', year: 2018 },
        { make: '    TOYOTA        ', model: '   LAND ROVER  ', year: '          2018            ' },
        { make: '   MERCEDES BENZ        ', model: '   C500     ', year: 2018 },
        { make: '   MERCEDES BENZ        ', model: '   C500     ', year: '        2018     ' },
      ].each do |v|
        vkey = Vehicles.generate_vkey(v[:make], v[:model], v[:year])
        expect(Vehicles.valid_vkey?(vkey)).to be true
        expect(vkey).to eq("#{v[:make].strip}|#{v[:model].strip}|#{v[:year].is_a?(String) ? v[:year].strip : v[:year]}".downcase)
      end
    end

  end

  describe 'Basic API' do

    it 'retrieves a campaign' do
      u = URI.parse('https://dummy.com/')
      expect(URI).to receive(:parse).with(/16V741000/).and_return(u)

      f = read_nhtsa('campaign1.json')
      expect(Net::HTTP).to receive(:get).with(u).and_return(f)

      json = JSON.parse(f)
      r = json['Results'].first
      v = json['Results'].map{|rv| Vehicle.new(make: rv['Make'], model: rv['Model'], year: rv['ModelYear'].to_i)}

      c = Vehicles::Basic.campaign_from_id('16V741000')
      expect(c).to be_a(Hash)
      expect(c).to include(campaign_id: r['NHTSACampaignNumber'])
      expect(c).to include(component: r['Component'])
      expect(c).to include(summary: r['Summary'])
      expect(c).to include(consequence: r['Conequence'])
      expect(c).to include(remedy: r['Remedy'])
      expect(c).to include(publication_date: Vehicles::Basic.convert_date(r['ReportReceivedDate']))
      expect(c[:vehicles]).to match(v)
    end

    it 'returns the Time corresponding to the Date' do
      date = Vehicles::Basic.convert_date('/Date(1559347200000-0000)/')
      expect(date).to eq(Time.new(2019, 6, 1).beginning_of_day.utc)
    end

    it 'returns the Time in UTC' do
      expect(Vehicles::Basic.convert_date('/Date(1559347200000-0000)/')).to be_utc
    end

    it 'applies the UTC offset to the Date' do
      date = Vehicles::Basic.convert_date('/Date(1559347200000-0400)/')
      expect(date).to eq(Time.new(2019, 6, 1, 0, 0, 0, '-04:00').utc)
    end

    it 'returns the current time if the Date is invalid' do
      freeze_time do
        now = Time.now.utc
        expect(Vehicles::Basic.convert_date('averybaddate')).to eq(now)
      end
    end

    it 'retrieves a vehicle given a VIN' do
      u = URI.parse('https://dummy.com/')
      expect(URI).to receive(:parse).with(/JTDKARFU0H3528314/).and_return(u)

      f = read_nhtsa('vin1.json')
      expect(Net::HTTP).to receive(:get).with(u).and_return(f)

      json = JSON.parse(f)
      make =
      model =
      year = nil
      json['Results'].each do |r|
        make = r['Value'] if r['VariableId'] == 26
        model = r['Value'] if r['VariableId'] == 28
        year = r['Value'].to_i if r['VariableId'] == 29
      end

      v = Vehicles::Basic.vehicle_from_vin('JTDKARFU0H3528314')
      expect(v).to be_a(Vehicle)
      expect(v.make).to eq(make)
      expect(v.model).to eq(model)
      expect(v.year).to eq(year)
    end

    it 'retrieves the campaigns given a vehicle' do
      u = URI.parse('https://dummy.com/')
      expect(URI).to receive(:escape).with(/fauxmake/ && /fauxmodel/ && /#{Time.now.year}/).and_return('https://dummy.com')
      expect(URI).to receive(:parse).with('https://dummy.com').and_return(u)

      f = read_nhtsa('vin_recalls1.json')
      expect(Net::HTTP).to receive(:get).and_return(f)

      json = JSON.parse(f)

      v = Vehicle.new(make: 'fauxmake', model: 'fauxmodel', year: Time.now.year)
      c = Vehicles::Basic.vehicle_campaigns(v)
      expect(c).to be_a(Array)
      expect(c).to match(json['Results'].map{|r| r['NHTSACampaignNumber']})
    end

  end

  describe 'Full API' do

    it 'retrieves a campaign' do
      u = URI.parse('https://dummy.com/')
      expect(URI).to receive(:parse).with(/16V741000/).and_return(u)

      f = read_nhtsa('campaign1.json', basic: false)
      expect(Net::HTTP).to receive(:get).with(u).and_return(f)

      json = JSON.parse(f)
      r = json['results'].first['recalls'].first
      v = r['associatedProducts'].map{|rv| Vehicle.new(make: rv['productMake'], model: rv['productModel'], year: rv['productYear'].to_i)}

      c = Vehicles::Full.campaign_from_id('16V741000')
      expect(c).to be_a(Hash)
      expect(c).to include(campaign_id: r['nhtsaCampaignNumber'])
      expect(c).to include(component: r['components'].first['name'])
      expect(c).to include(summary: r['summary'])
      expect(c).to include(consequence: r['consequence'])
      expect(c).to include(remedy: r['correctiveAction'])
      expect(c).to include(publication_date: Time.rfc3339(r['reportReceivedDate']))
      expect(c[:vehicles]).to match(v)
    end

    it 'retrieves a vehicle given a VIN' do
      u = URI.parse('https://dummy.com/')
      expect(URI).to receive(:parse).with(/JTDKARFU0H3528314/).and_return(u)

      f = read_nhtsa('vin1.json', basic: false)
      expect(Net::HTTP).to receive(:get).with(u).and_return(f)

      json = JSON.parse(f)
      r = json['results'].first
      make = r['make']
      model = r['vehicleModel']
      year = r['modelYear']

      v = Vehicles::Full.vehicle_from_vin('JTDKARFU0H3528314')
      expect(v).to be_a(Vehicle)
      expect(v.make).to eq(make)
      expect(v.model).to eq(model)
      expect(v.year).to eq(year)
    end

    it 'retrieves the campaigns given a vin' do
      u = URI.parse('https://dummy.com/')
      expect(URI).to receive(:parse).with(/JTDKARFU0H3528314/).and_return(u)

      f = read_nhtsa('vin_recalls1.json', basic: false)
      expect(Net::HTTP).to receive(:get).and_return(f)

      json = JSON.parse(f)
      r = json['results'].first['safetyIssues']['recalls']

      c = Vehicles::Full.vin_campaigns('JTDKARFU0H3528314')
      expect(c).to be_a(Array)
      expect(c).to match(r.map{|rr| rr['nhtsaCampaignNumber']})
    end

  end

end
