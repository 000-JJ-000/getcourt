require "test_helper"

class EmailLoginChallengeTest < ActiveSupport::TestCase
  test "stores only a digest of the code" do
    challenge, raw = EmailLoginChallenge.issue!(email: "digest@example.com")

    assert_equal 6, raw.length
    refute_equal raw, challenge.code_digest
    assert_equal EmailLoginChallenge.digest_code("digest@example.com", raw), challenge.code_digest
  end

  test "verify_code consumes a matching code once" do
    challenge, raw = EmailLoginChallenge.issue!(email: "once@example.com")

    assert_equal :ok, challenge.verify_code(raw)
    assert challenge.consumed?
    assert_equal :consumed, challenge.verify_code(raw)
  end

  test "issuing a new challenge invalidates prior active ones" do
    first, = EmailLoginChallenge.issue!(email: "replace@example.com")
    second, = EmailLoginChallenge.issue!(email: "replace@example.com")

    assert first.reload.consumed?
    assert_predicate second, :usable?
  end

  test "locks after too many failures" do
    challenge, raw = EmailLoginChallenge.issue!(email: "lock@example.com")

    EmailLoginChallenge::MAX_FAILED_ATTEMPTS.times do
      assert_includes %i[invalid locked], challenge.verify_code("000000")
    end

    assert_predicate challenge.reload, :locked?
    assert_equal :locked, challenge.verify_code(raw)
  end

  test "concurrent verify cannot consume the same code twice" do
    challenge, raw = EmailLoginChallenge.issue!(email: "race-consume@example.com")
    twin = EmailLoginChallenge.find(challenge.id)

    assert_equal :ok, challenge.verify_code(raw)
    assert_equal :consumed, twin.verify_code(raw)
  end
end
