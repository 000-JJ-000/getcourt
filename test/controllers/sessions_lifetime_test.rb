require "test_helper"

class SessionsLifetimeTest < ActionDispatch::IntegrationTest
  test "authenticated session expires after the absolute TTL" do
    sign_in_with_email("session-ttl@example.com")
    assert session[:user_id].present?
    assert session[:authenticated_at].present?

    get edit_account_url
    assert_response :success

    travel (Rails.application.config.x.session_absolute_ttl + 1.minute) do
      get edit_account_url
      assert_redirected_to new_session_path
      assert_nil session[:user_id]
    end
  ensure
    User.find_by(email: "session-ttl@example.com")&.destroy
  end

  test "sign in rotates the session and sets authenticated_at" do
    get new_session_url
    before = cookies["_get_court_session_v2"]

    sign_in_with_email("session-rotate-ttl@example.com")

    refute_equal before, cookies["_get_court_session_v2"]
    assert session[:authenticated_at].present?
    assert Time.iso8601(session[:authenticated_at]) > 1.minute.ago
  ensure
    User.find_by(email: "session-rotate-ttl@example.com")&.destroy
  end

  test "logout clears authentication even if the cookie is reused conceptually" do
    sign_in_with_email("session-logout-ttl@example.com")
    delete destroy_session_url

    assert_nil session[:user_id]
    assert_nil session[:authenticated_at]
    get edit_account_url
    assert_redirected_to new_session_path
  ensure
    User.find_by(email: "session-logout-ttl@example.com")&.destroy
  end
end
