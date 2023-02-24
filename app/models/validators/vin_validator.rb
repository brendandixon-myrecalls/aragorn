module Validations

  class VinValidator < ActiveModel::EachValidator
    
    # Note:
    # - Errors added to the model base instead of the attribute since the model
    #   and attribute share the same name
    def validate_each(record, attribute, value)
      if value.blank?
        record.errors.add(:base, "cannot be blank", options)
      else
        record.errors.add(:base, "#{value} is not well-formed", options) unless Vehicles.valid_vin?(value)
      end
    end

  end

  module HelperMethods
    # Validates whether the value is a well-formed VIN
    #
    def validates_is_vin(*attr_names)
      validates_with VinValidator, _merge_attributes(attr_names)
    end
  end

end
