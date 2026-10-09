require "test_helper"

class Sessions::EmailLoginTest < ActiveSupport::TestCase
  test "request rejects blank and invalid emails" do
    assert_equal :blank_email, Sessions::EmailLogin.request(email: "  ").error
    assert_equal :invalid_email, Sessions::EmailLogin.request(email: "not-an-email").error
  end

  test "verify provisions a user only after a correct code" do
    result = Sessions::EmailLogin.request(email: "provision@example.com", locale: "en", telegram_locale: "en")
    assert result.ok?

    bad = Sessions::EmailLogin.verify(challenge: result.challenge, code: "000000")
    refute bad.ok?
    assert_nil User.find_by(email: "provision@example.com")

    good = Sessions::EmailLogin.verify(challenge: result.challenge, code: result.raw_code)
    assert good.ok?
    assert_equal "provision@example.com", good.user.email
    assert_predicate good.user, :verified?
  end

  test "concurrent challenges: only the latest usable code works" do
    first = Sessions::EmailLogin.request(email: "race@example.com")
    second = Sessions::EmailLogin.request(email: "race@example.com")

    refute Sessions::EmailLogin.verify(challenge: first.challenge, code: first.raw_code).ok?
    assert Sessions::EmailLogin.verify(challenge: second.challenge, code: second.raw_code).ok?
  end
end
