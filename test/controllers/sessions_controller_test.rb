require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "should get new" do
    get new_session_url
    assert_response :success
  end

  test "sign-in page tells bot users how to link their existing account" do
    get new_session_url

    assert_response :success
    assert_select '[data-testid="telegram-signup-hint"]', 1
    assert_select '[data-testid="telegram-signup-hint"] summary', text: "Did you previously sign up through Telegram?"
    assert_select '[data-testid="telegram-signup-hint"] a[href=?]', notifications_account_path
  end

  test "email-only login no longer establishes a session" do
    email = "sessions_email_only@example.com"

    post session_url, params: { email: email, privacy_consent: "1", age_consent: "1" }

    assert_redirected_to verify_session_path
    assert_nil session[:user_id]
    assert_nil User.find_by(email: email)
    assert EmailLoginChallenge.active.exists?(email: email)
  end

  test "requesting a code for a new email does not create a user yet" do
    email = "sessions_pending_user@example.com"

    post session_url, params: { email: email }

    assert_redirected_to verify_session_path
    assert_nil User.find_by(email: email)
  end

  test "correct code authenticates and creates a new account" do
    email = "sessions_new_account@example.com"
    host! "en.getcourt.co"

    post session_url, params: { email: email }
    code = last_login_code

    post "/sign_in/verify", params: { code: code }

    assert_redirected_to root_path
    user = User.find_by!(email: email)
    assert_equal user.id, session[:user_id]
    assert_equal "en", user.telegram_locale
    assert_equal "en", user.locale
    assert_equal "email", user.registration_source
    assert_predicate user, :verified?
  ensure
    User.find_by(email: email)&.destroy
  end

  test "correct code signs in an existing account without merging strangers" do
    user = User.create!(email: "sessions_existing@example.com", locale: "ru", name: "Existing")

    post session_url, params: { email: user.email }
    post "/sign_in/verify", params: { code: last_login_code }

    assert_redirected_to root_path
    assert_equal user.id, session[:user_id]
    assert_equal "ru", user.reload.locale
    assert_equal "Existing", user.name
  ensure
    user&.destroy
  end

  test "new user created from es locale stores es telegram locale" do
    host! "es.getcourt.co"
    email = "sessions_es_locale@example.com"

    post session_url, params: { email: email }
    post "/sign_in/verify", params: { code: last_login_code }

    assert_redirected_to root_path
    user = User.find_by!(email: email)
    assert_equal "es", user.telegram_locale
    assert_equal "es", user.locale
  ensure
    User.find_by(email: email)&.destroy if defined?(email)
  end

  test "incorrect code fails and does not authenticate" do
    post session_url, params: { email: "sessions_bad_code@example.com" }

    post "/sign_in/verify", params: { code: "000000" }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_nil User.find_by(email: "sessions_bad_code@example.com")
  end

  test "expired code fails" do
    post session_url, params: { email: "sessions_expired@example.com" }
    challenge = EmailLoginChallenge.active.find_by!(email: "sessions_expired@example.com")
    code = last_login_code
    challenge.update_columns(expires_at: 1.minute.ago)

    post "/sign_in/verify", params: { code: code }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "reused code fails" do
    email = "sessions_reuse@example.com"
    post session_url, params: { email: email }
    code = last_login_code

    post "/sign_in/verify", params: { code: code }
    assert_equal User.find_by!(email: email).id, session[:user_id]

    delete destroy_session_url
    assert_nil session[:user_id]

    post "/sign_in/verify", params: { code: code }
    assert_response :redirect
    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  ensure
    User.find_by(email: email)&.destroy
  end

  test "excessive failed attempts lock the challenge" do
    post session_url, params: { email: "sessions_locked@example.com" }
    EmailLoginChallenge::MAX_FAILED_ATTEMPTS.times do
      post "/sign_in/verify", params: { code: "000000" }
      assert_response :unprocessable_entity
      assert_nil session[:user_id]
    end

    post "/sign_in/verify", params: { code: last_login_code }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "registered and unknown emails get the same challenge response shape" do
    User.create!(email: "sessions_known@example.com")

    post session_url, params: { email: "sessions_known@example.com" }
    known_location = response.headers["Location"]
    known_status = response.status

    post session_url, params: { email: "sessions_unknown_#{SecureRandom.hex(4)}@example.com" }
    unknown_location = response.headers["Location"]
    unknown_status = response.status

    assert_equal known_status, unknown_status
    assert_equal known_location, unknown_location
    assert_equal verify_session_path, URI(known_location).path
  end

  test "sign in rotates the session id" do
    get new_session_url
    before = session.id

    post session_url, params: { email: "sessions_rotate@example.com" }
    post "/sign_in/verify", params: { code: last_login_code }

    refute_equal before.to_s, session.id.to_s
    assert session[:user_id].present?
  ensure
    User.find_by(email: "sessions_rotate@example.com")&.destroy
  end

  test "logout invalidates the authenticated session" do
    sign_in_with_email("sessions_logout@example.com")
    assert session[:user_id].present?

    delete destroy_session_url

    assert_nil session[:user_id]
    get edit_account_url
    assert_redirected_to new_session_path
  ensure
    User.find_by(email: "sessions_logout@example.com")&.destroy
  end

  test "unverified input cannot take over an existing account" do
    victim = User.create!(email: "sessions_victim@example.com", name: "Victim")

    post session_url, params: { email: victim.email }
    assert_nil session[:user_id]
    assert_equal "Victim", victim.reload.name

    post "/sign_in/verify", params: { code: "111111" }
    assert_nil session[:user_id]
    assert_equal victim.id, User.find_by!(email: victim.email).id
  ensure
    victim&.destroy
  end

  test "mail delivery failure does not authenticate and consumes the challenge" do
    email = "sessions_mail_fail@example.com"
    stub_singleton(UserMailer, :login_code_email, ->(*) { raise StandardError, "smtp down" }) do
      post session_url, params: { email: email }
    end

    assert_redirected_to new_session_path
    assert_nil session[:user_id]
    assert_nil User.find_by(email: email)
    challenge = EmailLoginChallenge.order(:id).last
    assert challenge.present?
    assert_equal email, challenge.email
    assert challenge.consumed?
  end

  test "verify page requires an outstanding challenge in the session" do
    get verify_session_url
    assert_redirected_to new_session_path
  end

  test "resend issues a replacement code and invalidates the prior challenge" do
    email = "sessions_resend@example.com"
    post session_url, params: { email: email }
    first = EmailLoginChallenge.order(:id).last
    first_code = last_login_code

    post session_url, params: { email: email }
    second = EmailLoginChallenge.order(:id).last
    second_code = last_login_code

    refute_equal first.id, second.id
    assert first.reload.consumed?

    post "/sign_in/verify", params: { code: first_code }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]

    post "/sign_in/verify", params: { code: second_code }
    assert_redirected_to root_path
    assert session[:user_id].present?
  ensure
    User.find_by(email: email)&.destroy
  end

  test "should destroy session" do
    delete destroy_session_url
    assert_redirected_to new_session_path
  end
end
