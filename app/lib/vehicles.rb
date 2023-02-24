module Vehicles
  
  CAMPAIGN_IDENTIFIER_LENGTH = 9
  CAMPAIGN_LINK_REGEX = /\A.*nhtsaId=([[:alnum:]]{#{CAMPAIGN_IDENTIFIER_LENGTH}}).*\Z/
  CAMPAIGN_REGEX = /\A\s*[[:alnum:]]{#{CAMPAIGN_IDENTIFIER_LENGTH}}\s*\Z/

  VIN_LETTER_CODE = {
    'A' => 1,
    'B' => 2,
    'C' => 3,
    'D' => 4,
    'E' => 5,
    'F' => 6,
    'G' => 7,
    'H' => 8,

    'J' => 1,
    'K' => 2,
    'L' => 3,
    'M' => 4,
    'N' => 5,

    'P' => 7,

    'R' => 9,

    'S' => 2,
    'T' => 3,
    'U' => 4,
    'V' => 5,
    'W' => 6,
    'X' => 7,
    'Y' => 8,
    'Z' => 9
  }
  VIN_POSITION_WEIGHT = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]

  VIN_LENGTH = 17

  MAKE_PATTERN = '[[[:graph:]]\s]+'
  MAKE_REGEX = /\A\s*(#{MAKE_PATTERN})\s*\Z/

  MODEL_PATTERN = '[[[:graph:]]\s]+'
  MODEL_REGEX = /\A\s*(#{MODEL_PATTERN})\s*\Z/

  YEAR_PATTERN = '[[:digit:]]{4}'
  YEAR_REGEX = /\A\s*(#{YEAR_PATTERN})\s*\Z/

  VKEY_REGEX = /\A\s*(#{MAKE_PATTERN})\|(#{MODEL_PATTERN})\|(#{YEAR_PATTERN})\s*\Z/

  class<<self

    def valid_vin?(vin)
      vin = vin.to_s
      return false if vin.blank? || vin.length != VIN_LENGTH

      values = vin.upcase().split('').map{|n| (n =~ /[A-Z]/ ? VIN_LETTER_CODE[n] : n).to_i }
      sum = 0
      values.each_with_index{|n, i| sum += (n * VIN_POSITION_WEIGHT[i])}
      remainder = sum % 11
      vin[8] == (remainder == 10 ? 'X' : remainder.to_s)
    end

    def valid_vkey?(vkey)
      ((vkey || '') =~ VKEY_REGEX).present?
    end

    # Note:
    # - The conversion to a vkey is destructive in that it normalizes the strings to lowercase
    def generate_vkey(make, model, year)
      return unless make.present? && model.present? && year.present?
      "#{make.to_s.strip}|#{model.to_s.strip}|#{year.to_s.strip}".downcase
    end

  end

  # Basic NHTSA API (documented)
  #
  # Notes:
  # - See https://webapi.nhtsa.gov/Default.aspx?Recalls/API/83
  module Basic

    CAMPAIGN_ID = 'NHTSACampaignNumber'

    COMPONENT = 'Component'

    # Note:
    # - The NHTSA campaign JSON misspells "consequence" as "conequence"
    CONSEQUENCE = 'Conequence'
    COUNT = 'Count'

    # Note:
    # - NHTSA dates in JSON are JavaScript Date strings expressing UTC milliseconds
    #   since the epoch concatenated with the zone offset embedded in a RegEx, such as:
    #
    #   \/Date(1476417600000-0400)\/
    #
    # - Use a flexible, vs.strict, Regex by searching for the "Date" part of the string
    CAMPAIGN_DATE_REGEX = /.*Date\((\d{13})(\-\d{4})\).*/

    MAKE = 'Make'
    MAKE_ID = 26

    MODEL = 'Model'
    MODEL_ID = 28

    MODEL_YEAR = 'ModelYear'
    MODEL_YEAR_ID = 29

    PUBLICATION_DATE = 'ReportReceivedDate'

    REMEDY = 'Remedy'
    RESULTS = 'Results'
    SUMMARY = 'Summary'

    VARIABLE_ID = 'VariableId'
    VALUE = 'Value'

    class<<self

      def campaign_from_id(campaign_id)
        json = self.campaign_json(campaign_id)

        campaign = {
          vehicles: []
        }
        (json[RESULTS] || []).each do |result|
          campaign[:campaign_id] ||= result[CAMPAIGN_ID]

          campaign[:component] ||= (result[COMPONENT] || '').split(':').first || ''
          campaign[:summary] ||= result[SUMMARY]
          campaign[:consequence] ||= result[CONSEQUENCE]
          campaign[:remedy] ||= result[REMEDY]

          campaign[:publication_date] ||= self.convert_date(result[PUBLICATION_DATE])

          v = Vehicle.new(
                make: result[MAKE],
                model: result[MODEL],
                year: result[MODEL_YEAR].to_i)
          campaign[:vehicles] << v if v.valid?
        end

        campaign[:publication_date] ||= Time.now.utc
        campaign
      end

      def convert_date(date)
        m = date.match(CAMPAIGN_DATE_REGEX)
        return Time.now.utc unless m.present?
        return Time.at(m[1].to_i / 1000).advance(hours: -(m[2].to_i / 100)).utc;
      end

      def vehicle_from_vin(vin)
        json = self.vin_json(vin)

        vehicle = Vehicle.new
        (json[RESULTS] || []).each do |result|
          next unless [MAKE_ID, MODEL_ID, MODEL_YEAR_ID].include?(result[VARIABLE_ID])

          if result[VARIABLE_ID] == MAKE_ID
            vehicle.make = result[VALUE]
          elsif result[VARIABLE_ID] == MODEL_ID
            vehicle.model = result[VALUE]
          elsif result[VARIABLE_ID] == MODEL_YEAR_ID
            vehicle.year = result[VALUE].to_i
          end

          break if vehicle.valid?
        end

        vehicle.valid? ? vehicle : nil
      end

      def vehicle_campaigns(vehicle)
        json = self.recalls_json(vehicle)
        (json[RESULTS] || []).map{|result| result[CAMPAIGN_ID]}
      end

      protected

        def campaign_json(campaign_id)
          u = URI::parse("https://webapi.nhtsa.gov/api/Recalls/vehicle/campaignnumber/#{campaign_id}?format=json")
          JSON.parse(Net::HTTP.get(u)) rescue {}
        end

        def recalls_json(vehicle)
          return {} unless vehicle.is_a?(Vehicle) && vehicle.valid?
          s = "https://webapi.nhtsa.gov/api/Recalls/vehicle/modelyear/#{vehicle.year}/make/#{vehicle.make}/model/#{vehicle.model}?format=json"
          u = URI::parse(URI.escape(s))
          JSON.parse(Net::HTTP.get(u)) rescue {}
        end

        def vin_json(vin)
          u = URI::parse("https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVin/#{vin}?format=json")
          JSON.parse(Net::HTTP.get(u)) rescue {}
        end

    end

  end

  # Full NHTSA API (undocumented, used by NHTSA pages)
  #
  # NOTE:
  # - This API appear to now require an authN token
  #
  module Full

    CAMPAIGN_ID = 'nhtsaCampaignNumber'
    COMPONENTS = 'components'
    CONSEQUENCE = 'consequence'
    MAKE = 'make'
    MODEL = 'vehicleModel'
    MODEL_YEAR = 'modelYear'
    NAME = 'name'
    PUBLICATION_DATE = 'reportReceivedDate'
    RECALLS = 'recalls'
    REMEDY = 'correctiveAction'
    RESULTS = 'results'
    SAFETY_ISSUES = 'safetyIssues'
    SUMMARY = 'summary'

    PRODUCTS = 'associatedProducts'
    PRODUCT_TYPE = 'type'
    PRODUCT_TYPE_VEHICLE = 'Vehicle'
    PRODUCT_MAKE = 'productMake'
    PRODUCT_MODEL = 'productModel'
    PRODUCT_YEAR = 'productYear'

    class<<self

      def campaign_from_id(campaign_id)
        json = self.campaign_json(campaign_id)

        recall = (((json[RESULTS] || []).first || {})[RECALLS] || []).first

        campaign = {
          campaign_id: recall[CAMPAIGN_ID],

          component: ((recall[COMPONENTS] || []).first || {})[NAME] || '',
          summary: recall[SUMMARY],
          consequence: recall[CONSEQUENCE],
          remedy: recall[REMEDY],

          publication_date: (Time.rfc3339(recall[PUBLICATION_DATE]) rescue Time.now.utc),

          vehicles: []
        }

        (recall[PRODUCTS] || []).each do |product|
          next unless product[PRODUCT_TYPE] == PRODUCT_TYPE_VEHICLE
          v = Vehicle.new(
                make: product[PRODUCT_MAKE],
                model: product[PRODUCT_MODEL],
                year: product[PRODUCT_YEAR].to_i)
          campaign[:vehicles] << v if v.valid?
        end

        campaign
      end

      def vehicle_from_vin(vin)
        json = self.vin_json(vin)

        result = (json[RESULTS] || []).first || {}
        vehicle = Vehicle.new(
                    make: result[MAKE],
                    model: result[MODEL],
                    year: result[MODEL_YEAR].to_i)

        vehicle.valid? ? vehicle : nil
      end

      def vin_campaigns(vin)
        json = self.recalls_json(vin)
        recalls = (((json[RESULTS] || []).first || {})[SAFETY_ISSUES] || {})[RECALLS] || []
        recalls.map{|recall| recall[CAMPAIGN_ID]}
      end

      protected

        def campaign_json(campaign_id)
          u = URI::parse("https://api.nhtsa.gov/safetyIssues/byNhtsaId?nhtsaId=#{campaign_id}")
          JSON.parse(Net::HTTP.get(u)) rescue {}
        end

        def recalls_json(vin)
          # The NHTSA web page sends a query when using make, model, and year; the results include all submodels and so forth.
          # e.g., 'https://api.nhtsa.gov/vehicles/bySearch?offset=0&max=10&sort=id&data=none&productDetail=all&query="2017 toyota prius"'
          u = URI::parse("https://api.nhtsa.gov/vehicles/byVin?data=recalls&vin=#{vin}")
          JSON.parse(Net::HTTP.get(u)) rescue {}
        end

        def vin_json(vin)
          u = URI::parse("https://api.nhtsa.gov/vehicles/byVin?data=none&productDetail=all&vin=#{vin}")
          JSON.parse(Net::HTTP.get(u)) rescue {}
        end

    end

  end

end
