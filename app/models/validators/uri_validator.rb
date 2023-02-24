module Validations

  class UriValidator < ActiveModel::EachValidator
    
    def validate_each(record, attribute, value)
      if value.blank?
        record.errors[attribute] << (options[:message] || "cannot be blank")
      else
        value = (URI.parse(value) if value.is_a?(String)) rescue nil
        if value.blank?
          record.errors[attribute] << (options[:message] || "is not a well-formed URI (#{value} )")
        else
          schemes = options[:schemes] || ['http', 'https']
          schemes = [schemes] unless schemes.is_a?(Array)
          schemes = schemes.map{|scheme| scheme.to_s}
          record.errors[attribute] << (options[:message] || " uses an invalid URI scheme (#{value.scheme})") unless schemes.include?(value.scheme)
        end
      end
    end

  end

  module HelperMethods
    # Validates whether the value is a well-formed URI
    #
    # -- schemes: May list one or more URI schemes to allow (default is ['http', 'https'])
    #
    def validates_is_uri(*attr_names)
      validates_with UriValidator, _merge_attributes(attr_names)
    end
  end

end
