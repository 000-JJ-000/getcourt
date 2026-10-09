require "test_helper"

# Limits live in Rack::Attack; the test env uses :null_store, so counters would
# not persist. Swap in a memory store for these examples.
class LoginCodeThrottlingTest < ActionDispatch::IntegrationTest
  setup do
    @previous_enabled = Rack::Attack.enabled
    @previous_store = Rack::Attack.cache.store
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    @email = "throttled-login@example.com"
    post session_url, params: { email: @email }
    @code = last_login_code
  end

  teardown do
    Rack::Attack.cache.store = @previous_store
    Rack::Attack.enabled = @previous_enabled
    User.find_by(email: @email)&.destroy
    EmailLoginChallenge.where(email: @email).delete_all
  end

  test "wrong codes for one email run into the limit" do
    10.times { attempt(code: wrong_code) }
    assert_response :unprocessable_entity

    attempt(code: wrong_code)
    assert_response :too_many_requests

    # The right code is blocked too once the bucket is full.
    attempt(code: @code)
    assert_response :too_many_requests
    assert_nil session[:user_id]
  end

  test "the same limit covers every spelling of the route Rails accepts" do
    paths = [
      "/sign_in/verify",
      "/sign_in/verify.html",
      "/sign_in/verify.ht%6dl",
      "/sign_in/verify.html-foo",
      "/sign_in/verify/",
      "//sign_in/verify",
      "/sign_in//verify"
    ]
    paths.cycle.first(11).each { |path| attempt(code: wrong_code, path: path) }

    assert_response :too_many_requests
  end

  test "an oversized JSON body does not buy extra attempts" do
    padding = "x" * (70 * 1024)
    11.times do
      post "/sign_in/verify",
           params: { email: @email, code: wrong_code, padding: padding }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :too_many_requests
  end

  test "the counter follows the email Rails actually signs in with" do
    11.times do |index|
      post "/sign_in/verify?email=#{CGI.escape(@email)}",
           params: { email: "decoy-#{index}@example.com", code: wrong_code }
    end

    assert_response :too_many_requests
  end

  test "an email sent as JSON counts towards the same limit" do
    11.times do
      post "/sign_in/verify",
           params: { email: @email, code: wrong_code }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :too_many_requests
  end

  test "confirming token ownership runs into the address limit" do
    owner = User.create!(email: "token-confirm-throttle@example.com", email_verified_at: Time.current)
    sign_in_as(owner.email)

    31.times { post confirm_api_token_url, params: { code: "000000" } }

    assert_response :too_many_requests
  ensure
    owner&.destroy
  end

  test "one address cannot spray codes across many accounts" do
    31.times do |index|
      post "/sign_in/verify", params: { email: "sprayed-#{index}@example.com", code: wrong_code }
    end

    assert_response :too_many_requests
  end

  private

  def attempt(code:, path: "/sign_in/verify")
    post path, params: { email: @email, code: code }
  end

  def wrong_code
    @code == "000000" ? "111111" : "000000"
  end
end
