module Helper

  class<<self
    def generate_password
      p = generate_token
      p += Constants::LOWERCASE[rand(Constants::LOWERCASE.length)]
      p += Constants::UPPERCASE[rand(Constants::UPPERCASE.length)]
      p += Constants::DIGITS[rand(Constants::DIGITS.length)]
      p + Constants::SPECIAL[rand(Constants::SPECIAL.length)]
    end

    def generate_token
      SecureRandom::urlsafe_base64
    end

    def generate_access_token_expiration
      (Time.now + AragornConfig.token_duration).end_of_day
    end

    # Log JSON-API errors based on the embedded status code
    def log_errors(name, *errors)
      errors.each do |error|
        Rails.logger.send((error[:status] < 500 ? :warn : :error), "#{name} Exception: #{error.as_json}")
      end
    end

    # Return a psuedo-random number
    # - In test, this produces a stable series across runs
    def rand(n = 100)
      AragornConfig.prng.rand(n)
    end
  end

end
