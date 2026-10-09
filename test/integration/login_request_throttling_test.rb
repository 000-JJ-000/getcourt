require "test_helper"

class LoginRequestThrottlingTest < ActionDispatch::IntegrationTest
  setup do
    @previous_enabled = Rack::Attack.enabled
    @previous_store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rack::Attack.cache.store = @previous_store
    Rack::Attack.enabled = @previous_enabled
  end

  test "code requests for one email are rate limited" do
    email = "otp-request-throttle@example.com"

    5.times do
      post session_url, params: { email: email }
      assert_redirected_to verify_session_path
    end

    post session_url, params: { email: email }
    assert_response :too_many_requests
  end
end
