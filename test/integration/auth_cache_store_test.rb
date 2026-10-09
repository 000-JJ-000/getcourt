require "test_helper"
require "openssl"
require "uri"

# Production wires Rack::Attack and Telegram replay to Rails.cache (Solid Cache).
# This test asserts the shared-store contract without requiring multi-container CI.
class AuthCacheStoreTest < ActiveSupport::TestCase
  test "Rack::Attack uses Rails.cache after initialization" do
    assert_equal Rails.cache, Rack::Attack.cache.store
  end

  test "telegram initData replay is enforced through Rails.cache" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    bot = "cache-contract-token"
    ENV["TELEGRAM_BOT_TOKEN"] = bot

    init_data = signed_init_data(bot_token: bot, auth_date: Time.now.to_i, user: { id: 4242 })
    assert Telegram::WebAppAuth.verify(init_data, bot)
    assert_nil Telegram::WebAppAuth.verify(init_data, bot), "same hash must be rejected via shared cache"
  ensure
    Rails.cache = previous
  end

  private

  def signed_init_data(bot_token:, auth_date:, user:)
    params = {
      "auth_date" => auth_date.to_s,
      "user" => user.to_json
    }
    check_string = params.sort.map { |key, value| "#{key}=#{value}" }.join("\n")
    secret_key = OpenSSL::HMAC.digest("SHA256", "WebAppData", bot_token)
    params["hash"] = OpenSSL::HMAC.hexdigest("SHA256", secret_key, check_string)
    URI.encode_www_form(params)
  end
end
