class User < ApplicationRecord
  before_validation :normalize_email, :set_default_notification_channel, :normalize_ntrp_rating
  before_validation :set_default_registration_source, on: :create

  has_one :player_statistic, dependent: :destroy
  belongs_to :merged_into, class_name: "User", optional: true
  belongs_to :city, optional: true
  has_many :merged_users, class_name: "User", foreign_key: :merged_into_id, dependent: :nullify, inverse_of: :merged_into
  has_one_attached :avatar
  has_many :sent_match_invitations, class_name: "MatchInvitation", foreign_key: :inviter_id, dependent: :destroy, inverse_of: :inviter
  has_many :received_match_invitations, class_name: "MatchInvitation", foreign_key: :invitee_id, dependent: :destroy, inverse_of: :invitee
  after_create :ensure_player_statistic

  # Accounts merged into another one stay in the table for history, but must not
  # show up anywhere people are listed or picked.
  scope :not_merged, -> { where(merged_at: nil) }

  # People we can offer in a picker: those with a name, plus those who came from
  # the bot and have only a @nick.
  scope :identifiable, -> { where.not(name: [ nil, "" ]).or(where.not(telegram_username: [ nil, "" ])) }

  # Ordered by the label the picker shows (see ApplicationHelper#user_display_label),
  # so the list reads in the order it looks.
  scope :by_display_label, -> {
    order(Arel.sql("LOWER(COALESCE(NULLIF(users.name, ''), users.telegram_username, users.email))"))
  }

  # Подсказки для поля выбора игрока: по первым буквам имени, @ника или почты.
  # Фильтруем в Ruby, а не через LIKE: lower() в SQLite складывает регистр
  # только у латиницы, и «денис» не находил бы «Денис». Людей в базе десятки,
  # так что перебор дешевле, чем тащить ICU. Совпадения с начала слова идут
  # первыми — их и ждут, набирая первые буквы.
  def self.search_pickable(query, limit: 10)
    q = query.to_s.strip.downcase.delete_prefix("@")
    return [] if q.empty?

    matches = not_merged.identifiable.by_display_label.filter_map do |user|
      terms = user.picker_terms
      next unless terms.any? { |term| term.include?(q) }

      [ terms.any? { |term| term.start_with?(q) || term.split(/[\s._-]+/).any? { |word| word.start_with?(q) } } ? 0 : 1, user ]
    end
    matches.sort_by.with_index { |(rank, _user), index| [ rank, index ] }.map(&:last).first(limit)
  end

  # Всё, по чему человека ищут в подсказках, в нижнем регистре.
  def picker_terms
    [ name, User.normalize_telegram_username(telegram_username), email ].compact_blank.map(&:downcase)
  end

  SKILL_LEVELS = %w[beginner intermediate advanced pro].freeze
  SPORTS = SportCatalog::SPORTS
  PLAY_FORMATS = %w[singles doubles].freeze
  PLAY_STYLES = %w[casual competitive].freeze
  PROFILE_VISIBILITIES = %w[private members public].freeze
  AVAILABILITY_DAYS = %w[mon tue wed thu fri sat sun].freeze
  AVAILABILITY_PERIODS = %w[morning afternoon evening].freeze
  AVAILABILITY_NOTES_MAX = 200
  # Self-reported NTRP only (1.0–7.0 by half-steps). Not USTA-verified.
  NTRP_RATINGS = (2..14).map { |n| (BigDecimal(n) / 2) }.freeze
  AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  AVATAR_MAX_SIZE = 2.megabytes

  TIMEZONES = (
    TZInfo::Timezone.all_identifiers + ActiveSupport::TimeZone.all.map(&:name)
  ).uniq.freeze

  # One-time codes for API-token confirmation / account verification.
  # Web sign-in uses EmailLoginChallenge instead. Plaintext is never stored.
  LOGIN_CODE_TTL = 10.minutes
  LOGIN_CODE_DIGITS = 6

  def self.digest_login_code(email, code)
    EmailLoginChallenge.digest_code(email, code)
  end

  def generate_login_code!(via: "email")
    code = format("%0#{LOGIN_CODE_DIGITS}d", SecureRandom.random_number(10**LOGIN_CODE_DIGITS))
    update_columns(
      login_code: self.class.digest_login_code(email, code),
      login_code_sent_at: Time.current,
      login_via: via.to_s
    )
    code
  end

  def valid_login_code?(code, ttl_minutes: LOGIN_CODE_TTL / 1.minute)
    return false if login_code.blank? || login_code_sent_at.blank?
    return false if Time.current > (login_code_sent_at + ttl_minutes.minutes)

    digest = self.class.digest_login_code(email, code.to_s.strip)
    ActiveSupport::SecurityUtils.secure_compare(login_code.to_s, digest)
  end

  def clear_login_code!
    update_columns(login_code: nil, login_code_sent_at: nil, login_via: nil)
  end

  # store preferred_sports as JSON array in a text column, default empty array
  attribute :preferred_sports, :json, default: []
  attribute :skill_levels, :json, default: {}
  attribute :play_formats, :json, default: []
  attribute :play_styles, :json, default: []
  attribute :availability, :json, default: {}
  attribute :timezone, :string
  attribute :telegram_locale, :string
  attribute :recent_invite_handles, :json, default: []

  RECENT_INVITE_LISTS_LIMIT = 5

  TELEGRAM_LOCALES = %w[ru en es].freeze
  WEB_LOCALES = %w[en es ru].freeze
  NOTIFICATION_CHANNELS = %w[email telegram].freeze

  validates :telegram_locale, inclusion: { in: TELEGRAM_LOCALES }, allow_blank: true
  validates :locale, inclusion: { in: WEB_LOCALES }, allow_blank: true
  validates :notification_channel, inclusion: { in: NOTIFICATION_CHANNELS }

  # возвращает уровень для спорта (строка или nil)
  def skill_level_for(sport)
    skill_levels.to_h[sport]
  end

  def set_skill_level_for(sport, level)
    s = skill_levels.to_h
    if level.present?
      s[sport] = level
    else
      s.delete(sport)
    end
    update_column(:skill_levels, s)
  end

  def skill_level_display_for(sport)
    skill_level_for(sport)&.titleize
  end

  # валидации (опционально)
  validate :skill_levels_values_valid
  validate :play_formats_values_valid
  validate :play_styles_values_valid
  validate :availability_structure_valid
  validate :avatar_content_type_and_size

  has_many :games
  has_many :coached_games, class_name: "Game", foreign_key: :coach_id, dependent: :nullify, inverse_of: :coach
  has_many :second_coached_games, class_name: "Game", foreign_key: :second_coach_id, dependent: :nullify, inverse_of: :second_coach
  has_many :coach_prebookings, foreign_key: :coach_id, dependent: :destroy, inverse_of: :coach
  # Библиотека блоков тренировок принадлежит тренеру и уходит вместе с ним.
  has_many :training_blocks, dependent: :destroy
  has_many :training_plan_proposals, dependent: :destroy
  # Токены к MCP-серверу уходят вместе с аккаунтом: доступ выдан человеку.
  has_many :api_tokens, dependent: :destroy
  has_many :training_plan_votes, dependent: :destroy
  has_many :participations
  has_many :favorite_court_links, class_name: "FavoriteCourt", dependent: :destroy
  has_many :court_ratings, dependent: :destroy
  has_many :court_suggestions, dependent: :destroy
  has_many :reviewed_court_suggestions, class_name: "CourtSuggestion", foreign_key: :reviewed_by_id, dependent: :nullify, inverse_of: :reviewed_by
  has_many :favorite_courts, through: :favorite_court_links, source: :court

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :telegram_username, format: { with: /\A@?[\w\d_]{5,32}\z/, message: "is invalid" }, allow_blank: true
  validates :telegram_chat_id, uniqueness: true, allow_nil: true
  validates :skill_level, inclusion: { in: SKILL_LEVELS }, allow_nil: true
  validates :timezone, inclusion: { in: TIMEZONES }, allow_blank: true
  validates :profile_visibility, inclusion: { in: PROFILE_VISIBILITIES }
  validates :about_me, length: { maximum: 1000 }, allow_blank: true
  validate :ntrp_rating_allowed

  # return stored timezone or default (Yekaterinburg)
  def timezone_or_default
    read_attribute(:timezone).presence || "Asia/Yekaterinburg"
  end

  def admin?
    admin == true
  end

  # «Залогинен» само по себе не значит «это его почта». Подтверждением считаем
  # verified email OTP или a Telegram link on an account that has an email
  # (ghost /start rows with chat_id and no email are not verified).
  def verified?
    return true if email_verified_at.present?
    telegram_chat_id.present? && email.present?
  end

  def verify_email!
    update_columns(email_verified_at: Time.current) if email_verified_at.blank?
  end

  def skill_level_display
    skill_level&.titleize
  end

  def coach?
    self.coach == true
  end

  def profile_visibility_private?
    profile_visibility == "private"
  end

  def profile_visibility_members?
    profile_visibility == "members"
  end

  def profile_visibility_public?
    profile_visibility == "public"
  end

  # Incomplete / bot-only rows must not appear as community profiles.
  def community_profile_eligible?
    email.present? && !telegram_generated_email?
  end

  def profile_visible_to?(viewer)
    return true if viewer&.id == id
    return false unless community_profile_eligible?

    case profile_visibility
    when "public" then true
    when "members" then viewer.present?
    else false
    end
  end

  def invitable_by?(viewer)
    viewer.present? &&
      viewer.id != id &&
      accepts_match_invitations? &&
      community_profile_eligible? &&
      profile_visible_to?(viewer)
  end

  def ntrp_display
    return nil if ntrp_rating.blank?

    format("%.1f", ntrp_rating)
  end

  def availability_notes
    availability.to_h["notes"].to_s
  end

  def availability_for(day)
    Array(availability.to_h[day.to_s])
  end

  def play_preferences_present?
    play_formats.to_a.any? || play_styles.to_a.any?
  end

  def availability_present?
    hash = availability.to_h
    hash["notes"].present? || AVAILABILITY_DAYS.any? { |day| Array(hash[day]).any? }
  end

  # Compact weekday labels for directory cards (I18n done by the caller).
  def availability_days_present
    AVAILABILITY_DAYS.select { |day| availability_for(day).any? }
  end

  def avatar_variant(size: 160)
    return unless avatar.attached?

    avatar.variant(resize_to_fill: [ size, size ]).processed
  rescue StandardError => e
    Rails.logger.warn("[User##{id}] avatar variant failed: #{e.class}: #{e.message}")
    nil
  end

  # The newcomer checklist on the homepage: kept server-side on purpose, so closing
  # it on a laptop doesn't bring it back on a phone.
  def onboarding_dismissed?
    onboarding_dismissed_at.present?
  end

  def dismiss_onboarding!
    update_column(:onboarding_dismissed_at, Time.current)
  end

  # keep the latest invite lists handy, so the same group can be invited again in one click
  def remember_invite_handles(handles)
    handles = handles.map(&:to_s).uniq
    return if handles.empty?

    others = recent_invite_handles.to_a.reject { |list| list.sort == handles.sort }
    update_column(:recent_invite_handles, [ handles ] + others.first(RECENT_INVITE_LISTS_LIMIT - 1))
  end

  # Issue a link token only when Telegram is not already connected. Connected
  # accounts must call regenerate_* explicitly (re-link), so a leftover token
  # cannot silently hijack an existing chat binding.
  def ensure_telegram_registration_token!
    return nil if telegram_chat_id.present?
    return telegram_registration_token if telegram_registration_token.present?

    regenerate_telegram_registration_token!
  end

  def clear_telegram_registration_token!
    update_column(:telegram_registration_token, nil)
  end

  def regenerate_telegram_registration_token!
    loop do
      token = SecureRandom.hex(12)
      unless self.class.exists?(telegram_registration_token: token)
        update_column(:telegram_registration_token, token)
        return token
      end
    end
  end

  def notify_via_telegram(text)
    return false unless telegram_chat_id.present?
    TelegramNotifier.send_message(telegram_chat_id, text)
  rescue => e
    Rails.logger.warn "Telegram send failed for User##{id}: #{e.message}"
    false
  end

  # Ник, каким человек подписан в телеграме. Валидация поля пропускает и @,
  # и пробелы по краям, поэтому канонический вид собираем здесь — как с
  # City.normalize_name, чтобы правило жило в одном месте.
  TELEGRAM_USERNAME_FORMAT = /\A[A-Za-z0-9_]{5,32}\z/

  def self.normalize_telegram_username(value)
    candidate = value.to_s.strip.delete_prefix("@")
    return nil unless candidate.match?(TELEGRAM_USERNAME_FORMAT)

    candidate
  end

  def telegram_handle
    nick = self.class.normalize_telegram_username(telegram_username)
    "@#{nick}" if nick
  end

  # Подпись автора в рассылках. E-mail сюда не попадает намеренно: письмо
  # уходит всей команде, и почта одного игрока не должна становиться известной
  # остальным. Если ни имени, ни ника нет — nil, и текст идёт без автора.
  def broadcast_label
    parts = [ name.presence, telegram_handle ].compact
    return nil if parts.empty?

    parts.length == 2 ? "#{parts.first} (#{parts.last})" : parts.first
  end

  private

  def ensure_player_statistic
    create_player_statistic unless player_statistic
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
    true  # явно возвращаем true
  end

  def set_default_registration_source
    self.registration_source = "email" if registration_source.blank?
    true  # явно возвращаем true
  end

  def set_default_notification_channel
    self.notification_channel ||= telegram_chat_id.present? ? "telegram" : "email"
  end

  def normalize_ntrp_rating
    self.ntrp_rating = nil if ntrp_rating.blank?
  end

  def ntrp_rating_allowed
    return if ntrp_rating.nil?

    value = BigDecimal(ntrp_rating.to_s)
    return if NTRP_RATINGS.any? { |allowed| (value - allowed).abs < BigDecimal("0.001") }

    errors.add(:ntrp_rating, :inclusion)
  end

  def skill_levels_values_valid
    return if skill_levels.blank?
    unless skill_levels.is_a?(Hash)
      errors.add(:skill_levels, "must be a hash")
      return
    end

    skill_levels.each do |sport, level|
      next if level.blank?
      unless SPORTS.include?(sport) && SKILL_LEVELS.include?(level)
        errors.add(:skill_levels, "contains invalid entry for #{sport}")
      end
    end
  end

  def play_formats_values_valid
    list = play_formats
    unless list.is_a?(Array)
      errors.add(:play_formats, :invalid)
      return
    end

    return if list.empty?
    return if list.all? { |item| PLAY_FORMATS.include?(item.to_s) }

    errors.add(:play_formats, :invalid)
  end

  def play_styles_values_valid
    list = play_styles
    unless list.is_a?(Array)
      errors.add(:play_styles, :invalid)
      return
    end

    return if list.empty?
    return if list.all? { |item| PLAY_STYLES.include?(item.to_s) }

    errors.add(:play_styles, :invalid)
  end

  def availability_structure_valid
    hash = availability
    unless hash.is_a?(Hash)
      errors.add(:availability, :invalid)
      return
    end

    hash.each do |key, value|
      key = key.to_s
      if key == "notes"
        if value.to_s.length > AVAILABILITY_NOTES_MAX
          errors.add(:availability, :too_long)
        end
        next
      end

      unless AVAILABILITY_DAYS.include?(key)
        errors.add(:availability, :invalid)
        next
      end

      periods = Array(value)
      unless periods.all? { |period| AVAILABILITY_PERIODS.include?(period.to_s) }
        errors.add(:availability, :invalid)
      end
    end
  end

  def avatar_content_type_and_size
    return unless avatar.attached?

    unless AVATAR_CONTENT_TYPES.include?(avatar.blob.content_type)
      errors.add(:avatar, :invalid_type)
      avatar.purge
      return
    end

    return if avatar.blob.byte_size <= AVATAR_MAX_SIZE

    errors.add(:avatar, :too_large)
    avatar.purge
  end
end
