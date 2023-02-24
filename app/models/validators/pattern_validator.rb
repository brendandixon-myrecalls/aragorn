module Validations

  module HelperMethods

    # Validates whether the value is a legally formed email address
    #
    # validates_email :an_email
    #
    # See http://www.regular-expressions.info/email.html
    def validates_email(*attr_names, **options)
      options[:with] = Constants::EMAIL_PATTERN
      options[:message] = "has a malformed email address"
      validates_format_of attr_names, options
    end

    # Validates the string Recall identifier
    #
    # validates_recall_id :the_recall_id
    #
    def validates_recall_id(*attr_names, **options)
      options[:with] = Recall::ID_PATTERN
      options[:message] = 'has a malformed Recall identifier'
      validates_format_of attr_names, options
    end

    # Validates whether the value is an acceptable password
    #
    # validates_password :a_password
    #
    def validates_password(*attr_names, **options)
      options[:with] = Constants::PASSWORD_PATTERN
      options[:message] = "is a weak password - it must have one lower-case letter, one upper-case letter, a number, and a special character (i.e., !, @, #, $, %, ^, &, *)"
      validates_format_of attr_names, options
    end

    # Validates whether the value is a legally formed phone number
    #
    # validates_phone :a_phone
    #
    def validates_phone(*attr_names, **options)
      options[:with] = Constants::PHONE_PATTERN
      options[:message] = "has a malformed phone number"
      validates_format_of attr_names, options
    end

  end

end
