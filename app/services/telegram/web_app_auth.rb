require "openssl"
require "uri"

module Telegram
  class WebAppAuth
    # Short window limits replay of captured initData. Replay of the same hash
    # within the window is rejected via Rails.cache (shared in production).
    MAX_AGE = 1.hour.to_i
    FUTURE_SKEW = 60

    def self.verify(init_data, bot_token)
      params = URI.decode_www_form(init_data.to_s).to_h
      hash = params.delete("hash")
      return nil if hash.blank? || bot_token.blank?

      auth_date = params["auth_date"].to_i
      now = Time.now.to_i
      return nil if auth_date <= 0
      return nil if auth_date > now + FUTURE_SKEW
      return nil if now - auth_date > MAX_AGE

      check_string = params.sort.map { |key, value| "#{key}=#{value}" }.join("\n")
      secret_key = OpenSSL::HMAC.digest("SHA256", "WebAppData", bot_token)
      computed = OpenSSL::HMAC.hexdigest("SHA256", secret_key, check_string)
      return nil unless ActiveSupport::SecurityUtils.secure_compare(computed, hash)

      # First writer wins; a second use of the same signed payload is a replay.
      replay_key = "telegram_webapp_init:#{hash}"
      unless Rails.cache.write(replay_key, true, expires_in: MAX_AGE, unless_exist: true)
        return nil
      end

      params
    rescue ArgumentError
      nil
    end
  end
end
