# Shared passwordless sign-in for integration/system tests.
# POST /sign_in only issues an OTP; a session requires a successful verify.
module AuthenticationHelper
  def sign_in_as(user_or_email)
    email = user_or_email.respond_to?(:email) ? user_or_email.email : user_or_email.to_s
    sign_in_with_email(email)
    User.find_by!(email: EmailLoginChallenge.normalize_email(email))
  end

  def sign_in_with_email(email)
    sign_in_on(self, email)
  end

  # Works for the default integration session and for open_session handles.
  def sign_in_on(session_obj, email)
    email = EmailLoginChallenge.normalize_email(email)
    deliveries_before = ActionMailer::Base.deliveries.size

    session_obj.post session_url, params: { email: email, privacy_consent: "1", age_consent: "1" }
    location = session_obj.response.location.presence || session_obj.response.redirect_url
    assert location.present?, "expected redirect to verify for #{email}, got #{session_obj.response.status}"
    assert_equal verify_session_path, URI.parse(location).path, "expected OTP challenge for #{email}"

    mail = ActionMailer::Base.deliveries.drop(deliveries_before).last
    assert mail, "expected login code email for #{email}"
    code = extract_login_code_from_mail(mail)
    assert code, "expected 6-digit code in mail for #{email}"

    session_obj.post "/sign_in/verify", params: { code: code }
    assert session_obj.session[:user_id].present?, "expected authenticated session for #{email}"
  end

  def extract_login_code_from_mail(mail)
    bodies = [ mail.body.to_s ]
    bodies << mail.text_part.body.to_s if mail.multipart? && mail.text_part
    bodies << mail.html_part.body.to_s if mail.multipart? && mail.html_part
    bodies.join("\n")[/\b(\d{6})\b/, 1]
  end

  def last_login_code
    mail = ActionMailer::Base.deliveries.last
    assert mail, "expected a delivered login email"
    code = extract_login_code_from_mail(mail)
    assert code, "expected 6-digit code in last mail"
    code
  end
end

module ActionDispatch
  class IntegrationTest
    include AuthenticationHelper
  end
end
