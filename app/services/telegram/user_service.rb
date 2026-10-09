module Telegram
  class UserService
    # Найти или создать пользователя по данным чата Telegram.
    # Возвращает [user, created_bool]
    def self.find_or_create_for_chat(chat_hash, language_code: nil)
      Rails.logger.info("[BOT] UserService.find_or_create_for_chat chat=#{chat_hash.inspect}")
      chat_id  = chat_hash["id"].to_s
      username = chat_hash["username"].to_s.presence
      first_name = (chat_hash["first_name"] || chat_hash.dig("from", "first_name")).to_s.presence || "Telegram user"

      # 1) уже привязан по chat_id
      if (u = User.find_by(telegram_chat_id: chat_id))
        update_telegram_locale(u, language_code)
        return [ u, false ]
      end

      # Username alone must not bind chat_id — that allowed takeover of web
      # accounts that only stored a telegram_username. Link via /register token.

      # 2) создать минимальный аккаунт, пометить источник и сгенерировать сложный email
      random_email = "tg-#{SecureRandom.hex(18)}@telegram.getcourt"
      u = nil

      User.transaction do
        u = User.create!(
          email: random_email,
          name: first_name,
          telegram_username: username,
          telegram_chat_id: chat_id,
          telegram_locale: Telegram::I18n.locale_from_language_code(language_code),
          registration_source: "telegram",
          telegram_generated_email: true
        )
        Rails.logger.info("[BOT] created user id=#{u.id} email=#{u.email}")
      end

      [ u, true ]
    rescue ActiveRecord::RecordNotUnique => e
      Rails.logger.warn "Telegram UserService race condition: #{e.message}"
      [ User.find_by(telegram_chat_id: chat_id), false ]
    end

    def self.update_telegram_locale(user, language_code)
      locale = Telegram::I18n.locale_from_language_code(language_code)
      user.update_column(:telegram_locale, locale) if locale && user.telegram_locale.blank?
    end
    private_class_method :update_telegram_locale
  end
end
