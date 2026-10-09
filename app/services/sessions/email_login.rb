module Sessions
  # Issues and verifies passwordless email login challenges without revealing
  # whether the address already has an account.
  class EmailLogin
    Result = Struct.new(:ok, :challenge, :user, :error, :raw_code, keyword_init: true) do
      def ok?
        !!ok
      end
    end

    EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\z/

    def self.request(email:, ip: nil, locale: nil, telegram_locale: nil)
      new.request(email: email, ip: ip, locale: locale, telegram_locale: telegram_locale)
    end

    def self.verify(challenge:, code:)
      new.verify(challenge: challenge, code: code)
    end

    def request(email:, ip: nil, locale: nil, telegram_locale: nil)
      normalized = EmailLoginChallenge.normalize_email(email)
      return Result.new(ok: false, error: :blank_email) if normalized.blank?
      return Result.new(ok: false, error: :invalid_email) unless normalized.match?(EMAIL_FORMAT)

      challenge, raw_code = EmailLoginChallenge.issue!(
        email: normalized,
        ip: ip,
        locale: locale,
        telegram_locale: telegram_locale
      )
      Result.new(ok: true, challenge: challenge, raw_code: raw_code)
    end

    def verify(challenge:, code:)
      return Result.new(ok: false, error: :missing_challenge) if challenge.blank?

      case challenge.verify_code(code)
      when :ok
        user = provision_user!(challenge)
        Result.new(ok: true, challenge: challenge, user: user)
      when :expired
        Result.new(ok: false, error: :expired, challenge: challenge)
      when :consumed
        Result.new(ok: false, error: :consumed, challenge: challenge)
      when :locked
        Result.new(ok: false, error: :locked, challenge: challenge)
      else
        Result.new(ok: false, error: :invalid, challenge: challenge)
      end
    end

    private

    def provision_user!(challenge)
      user = User.find_or_initialize_by(email: challenge.email)
      if user.new_record?
        user.name = challenge.email.split("@").first.titleize
        user.registration_source = "email"
      end

      if User::WEB_LOCALES.include?(challenge.locale.to_s) && (user.new_record? || user.locale.blank?)
        user.locale = challenge.locale
      end
      if user.new_record? && User::TELEGRAM_LOCALES.include?(challenge.telegram_locale.to_s)
        user.telegram_locale = challenge.telegram_locale
      end

      user.save!
      user.verify_email! if user.respond_to?(:verify_email!)
      user
    end
  end
end
