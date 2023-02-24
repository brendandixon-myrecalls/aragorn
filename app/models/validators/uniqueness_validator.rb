module Validations

  class UniquenessValidator < ActiveModel::EachValidator
    
    def validate_each(record, attribute, value)
      if value.blank?
        record.errors[attribute] << (options[:message] || "cannot be blank")
      else
        conditions = [{ _id: {'$ne' => record._id}}, {attribute.to_sym => value}]
        if options.has_key?(:scope)
          scope = options[:scope]
          scope = [scope] unless scope.is_a?(Array)
          scope.each do |field|
            field = field.to_sym
            conditions << {field => record[field]}
          end
        end
        record.errors[attribute] << (options[:message] || "of #{value} is already taken") if record.class.and(conditions).exists?
      end
    end

  end

  module HelperMethods
    # Validates whether the value is unique within the database
    #
    # validates_email :an_email
    #
    def validates_uniqueness_of(*attr_names)
      validates_with UniquenessValidator, _merge_attributes(attr_names)
    end

  end

end
