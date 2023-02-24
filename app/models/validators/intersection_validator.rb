module Validations

  class IntersectionValidator < ActiveModel::EachValidator
    
    def validate_each(record, attribute, value)
      values = options[:in].is_a?(Proc) ? options[:in].call(record) : options[:in]
      return if values.blank? && value.blank?
      if values.present? && value.blank?
        record.errors[attribute] << (options[:message] || "cannot be blank")
      elsif values.present? && !value.is_a?(Array)
        record.errors[attribute] << (options[:message] || "must be a list of values")
      elsif values.blank? && value.present?
        record.errors[attribute] << (options[:message] || "must be empty")
      else
        if (value & values).length <= 0
          record.errors[attribute] << (options[:message] || "must be one or more of #{values.join(', ')}")
        elsif (value - values).length > 0
          record.errors[attribute] << (options[:message] || "must contain only one or more of #{values.join(', ')}")
        end
      end
    end

  end

  module HelperMethods
    # Validates whether the value is an array whose values come from
    # a particular enumerable object.
    #
    # validates_intersection_of :an_array, in: %w(a b c d)
    #
    def validates_intersection_of(*attr_names)
      validates_with IntersectionValidator, _merge_attributes(attr_names)
    end
  end

end
