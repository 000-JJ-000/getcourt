require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test

  include AuthenticationHelper

  def system_sign_in(user)
    visit new_session_path
    fill_in "Email", with: user.email
    check "privacy_consent" if page.has_field?("privacy_consent", wait: 0)
    check "age_consent" if page.has_field?("age_consent", wait: 0)
    click_on "Enter"

    assert_text(/verification code|код/i)
    code = last_login_code
    fill_in "Code", with: code
    click_on "Verify"
    assert_text "Signed in as #{user.email}"
  end
end
