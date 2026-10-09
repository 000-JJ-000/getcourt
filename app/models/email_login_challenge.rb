# Passwordless email login challenge. The plaintext code is never persisted —
# only an HMAC digest bound to the email address.
class EmailLoginChallenge < ApplicationRecord
  CODE_TTL = 10.minutes
  CODE_DIGITS = 6
  MAX_FAILED_ATTEMPTS = 5

  scope :active, -> {
    where(consumed_at: nil).where("expires_at > ?", Time.current)
  }

  validates :email, :code_digest, :expires_at, presence: true

  def self.normalize_email(value)
    value.to_s.strip.downcase.presence
  end

  def self.digest_code(email, code)
    material = "#{normalize_email(email)}:#{code.to_s.strip}"
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, material)
  end

  def self.issue!(email:, ip: nil, locale: nil, telegram_locale: nil)
    email = normalize_email(email)
    raise ArgumentError, "email required" if email.blank?

    # Invalidate outstanding challenges for this email so only the latest code works.
    active.where(email: email).update_all(consumed_at: Time.current)

    raw_code = format("%0#{CODE_DIGITS}d", SecureRandom.random_number(10**CODE_DIGITS))
    challenge = create!(
      email: email,
      code_digest: digest_code(email, raw_code),
      expires_at: CODE_TTL.from_now,
      request_ip: ip,
      locale: locale,
      telegram_locale: telegram_locale
    )
    [ challenge, raw_code ]
  end

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def locked?
    failed_attempts >= MAX_FAILED_ATTEMPTS
  end

  def usable?
    !consumed? && !expired? && !locked?
  end

  # Returns :ok, :invalid, :expired, :consumed, or :locked.
  # Successful consume is conditional on consumed_at still NULL so concurrent
  # verifies cannot both authenticate with the same code.
  def verify_code(code)
    reload if persisted?
    return :consumed if consumed?
    return :expired if expired?
    return :locked if locked?

    digest = self.class.digest_code(email, code)
    if ActiveSupport::SecurityUtils.secure_compare(code_digest, digest)
      rows = self.class.where(id: id, consumed_at: nil).update_all(
        consumed_at: Time.current,
        updated_at: Time.current
      )
      return :consumed if rows != 1

      reload
      :ok
    else
      increment!(:failed_attempts)
      locked? ? :locked : :invalid
    end
  end
end
