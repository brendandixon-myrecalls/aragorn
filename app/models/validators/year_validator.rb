module Validations

  class YearValidator < ActiveModel::EachValidator
    
    def validate_each(record, attribute, value)
      if value.blank?
        record.errors[attribute] << (options[:message] || "cannot be blank")
      elsif !value.is_a?(Integer) || !value.to_s.match?(/\d{4}/)
        record.errors[attribute] << "must be a four-digit integer"
      else
        min = options[:minimum] || options[:min]
        min = (min.is_a?(Proc) ? min.call(record) : min) || 0
        record.errors[attribute] << "must be greater than or equal to #{min}" unless value >= min

        max = options[:maximum] || options[:max]
        max = (max.is_a?(Proc) ? max.call(record) : max) || 9999
        record.errors[attribute] << "must be less than or equal to #{max}" unless value <= max
      end
    end

  end

  module HelperMethods
    # Validates whether the value is a valid year
    #
    # -- minimum or min: minimum acceptable year or lambda
    # -- maximum or max: maximum acceptable year or lambda
    #
    def validates_is_year(*attr_names)
      validates_with YearValidator, _merge_attributes(attr_names)
    end
  end

end
