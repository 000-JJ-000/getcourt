class UserMailer < ApplicationMailer
  # Accepts email string or User — web login may not have a User row yet.
  def login_code_email(recipient, code)
    @code = code
    email = recipient.is_a?(User) ? recipient.email : recipient.to_s
    locale =
      if recipient.is_a?(User)
        recipient.telegram_locale.presence || recipient.locale.presence || I18n.default_locale
      else
        I18n.default_locale
      end

    I18n.with_locale(locale) do
      mail(to: email, subject: t("user_mailer.login_code_email.subject"))
    end
  end

  def urgent_player_search(user, game)
    @user = user
    @game = game
    @game_url = game_url(game)
    @notifications_url = notifications_account_url
    locale = user.locale.to_s.presence_in(User::WEB_LOCALES) || I18n.default_locale

    I18n.with_locale(locale) do
      @owner = game.user.name.presence || t("user_mailer.urgent_player_search.organizer_fallback", id: game.user.id)
      @date = l((game.next_date || game.date).to_date, format: :long)
      @time = game.time&.strftime("%H:%M")
      formatter = Telegram::Helpers::GameFormatting
      @sport = formatter.sport_label(game.sport, locale: locale) || t("user_mailer.urgent_player_search.any_sport")
      @skill = formatter.skill_level_label(game.skill_level, locale: locale)

      mail(
        to: user.email,
        subject: t("user_mailer.urgent_player_search.subject", city: game.court.city_name)
      )
    end
  end

  def notification(user, subject:, body:, actions: [])
    @body = body
    @actions = actions
    @notifications_url = notifications_account_url
    locale = NotificationDelivery.email_locale(user)

    I18n.with_locale(locale) do
      mail(to: user.email, subject: subject)
    end
  end
end
