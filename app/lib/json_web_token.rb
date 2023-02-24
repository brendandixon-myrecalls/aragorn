# Note:
# - See https://jwt.io/ for details on using
class JsonWebToken

  class << self
    def encode(user_id, exp = Helper.generate_access_token_expiration)
      payload = {
        exp: exp.to_i,
        user_id: user_id.to_s,
        version: SecureRandom.alphanumeric(20),
      }
      JWT.encode(payload, Rails.application.secrets.secret_key_base)
    end

    def decode(token, exp_after = 10.minutes.from_now)
      payload = extract_payload(token, exp_after)
      payload[:user_id]
    rescue
      raise Authentication::AuthenticationError.new
    end

    def expires_at(token, exp_after = 10.minutes.from_now)
      payload = extract_payload(token, exp_after)
      payload[:exp]
    rescue
      Constants::ALWAYS
    end

    def valid?(token, user_id, exp_after = 10.minutes.from_now)
      raise unless decode(token, exp_after) == user_id.to_s
      true
    rescue
      false
    end

    protected
    
      def extract_payload(token, exp_after = 10.minutes.from_now)
        payload = JWT.decode(token, Rails.application.secrets.secret_key_base, true)[0]
        payload = HashWithIndifferentAccess.new payload
        payload[:exp] = Time.at(payload[:exp])
        raise unless payload[:exp].acts_like?(:time) && payload[:exp] > exp_after
        raise unless payload[:user_id].present? && payload[:user_id] =~ Constants::BSON_ID_PATTERN
        raise unless payload[:version].present? && payload[:version] =~ /[\w\d]{20,20}/
        payload
      end

  end

end
