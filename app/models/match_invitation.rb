class MatchInvitation < ApplicationRecord
  STATUSES = %w[pending accepted declined canceled expired].freeze
  SCHEDULING_STATUSES = %w[none needed proposed scheduled].freeze
  PLAY_FORMATS = %w[singles doubles].freeze
  MESSAGE_MAX = 500
  PROPOSAL_NOTE_MAX = 500
  DEFAULT_TTL = 7.days
  PENDING_PER_SENDER_LIMIT = 20
  SCHEDULING_REMINDER_AFTER = 2.days

  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"
  belongs_to :game, optional: true
  belongs_to :court, optional: true
  belongs_to :proposed_by, class_name: "User", optional: true

  validates :play_format, inclusion: { in: PLAY_FORMATS }
  validates :status, inclusion: { in: STATUSES }
  validates :scheduling_status, inclusion: { in: SCHEDULING_STATUSES }
  validates :message, length: { maximum: MESSAGE_MAX }, allow_blank: true
  validates :proposal_note, length: { maximum: PROPOSAL_NOTE_MAX }, allow_blank: true
  validates :expires_at, presence: true
  validate :invitee_must_differ
  validate :invitee_must_be_invitable, on: :create
  validate :no_duplicate_pending, on: :create

  before_validation :assign_defaults, on: :create

  scope :pending, -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }
  scope :involving, ->(user) { where(inviter_id: user.id).or(where(invitee_id: user.id)) }
  scope :received_by, ->(user) { where(invitee_id: user.id) }
  scope :sent_by, ->(user) { where(inviter_id: user.id) }
  scope :needs_scheduling, -> { accepted.where(scheduling_status: %w[needed proposed]) }
  scope :pending_expired, -> { pending.where(expires_at: ..Time.current) }
  scope :due_for_scheduling_reminder, -> {
    accepted.where(scheduling_status: "needed", scheduling_reminded_at: nil)
      .where(responded_at: ..SCHEDULING_REMINDER_AFTER.ago)
  }

  def pending?
    status == "pending"
  end

  def accepted?
    status == "accepted"
  end

  def scheduling_needed?
    scheduling_status == "needed"
  end

  def scheduling_proposed?
    scheduling_status == "proposed"
  end

  def scheduled?
    scheduling_status == "scheduled"
  end

  def expired_by_time?
    expires_at.present? && expires_at <= Time.current
  end

  def visible_to?(user)
    user.present? && (user.id == inviter_id || user.id == invitee_id)
  end

  def participant?(user)
    visible_to?(user)
  end

  def other_participant(user)
    return invitee if user&.id == inviter_id
    return inviter if user&.id == invitee_id

    nil
  end

  def awaiting_confirmation_from
    return nil unless scheduling_proposed? && proposed_by_id.present?

    proposed_by_id == inviter_id ? invitee : inviter
  end

  def open_doubles_slots
    return 0 unless play_format == "doubles" && game.present?

    [ game.spots_left, 0 ].max
  end

  def expire_if_needed!
    return self unless pending? && expired_by_time?

    with_lock do
      reload
      update!(status: "expired", responded_at: Time.current) if pending? && expired_by_time?
    end
    self
  end

  def accept!(by:)
    transition!(by: by, to: "accepted", role: :invitee) do
      finalize_accept_scheduling!
    end
  end

  def decline!(by:)
    transition!(by: by, to: "declined", role: :invitee)
  end

  def cancel!(by:)
    transition!(by: by, to: "canceled", role: :inviter)
  end

  # Either participant may propose or change a schedule while accepted and unscheduled.
  def propose_schedule!(by:, proposed_at:, court_id: nil, note: nil)
    raise ArgumentError, "unauthorized" unless participant?(by)
    raise ArgumentError, "not_accepted" unless accepted?
    raise ArgumentError, "already_scheduled" if scheduled? || game_id.present?

    at = parse_proposed_at!(proposed_at)
    raise ArgumentError, "invalid_time" if at <= Time.current

    court = resolve_court!(court_id)

    with_lock do
      reload
      raise ArgumentError, "not_accepted" unless accepted?
      raise ArgumentError, "already_scheduled" if scheduled? || game_id.present?

      update!(
        proposed_at: at,
        court: court,
        proposal_note: note.to_s.strip.presence,
        proposed_by: by,
        proposal_updated_at: Time.current,
        scheduling_status: "proposed"
      )
    end
    self
  end

  def confirm_schedule!(by:, proposal_updated_at:)
    raise ArgumentError, "unauthorized" unless participant?(by)

    with_lock do
      reload
      raise ArgumentError, "not_accepted" unless accepted?
      raise ArgumentError, "already_scheduled" if scheduled? || game_id.present?
      raise ArgumentError, "not_proposed" unless scheduling_proposed?
      raise ArgumentError, "cannot_confirm_own" if proposed_by_id == by.id
      raise ArgumentError, "stale_proposal" unless same_proposal_timestamp?(proposal_updated_at)
      raise ArgumentError, "invalid_time" if proposed_at.blank? || proposed_at <= Time.current

      create_peer_game!
      update!(scheduling_status: "scheduled", responded_at: responded_at || Time.current)
    end
    self
  end

  def players_count_for_format
    play_format == "doubles" ? 4 : 2
  end

  private

  def assign_defaults
    self.status ||= "pending"
    self.scheduling_status ||= "none"
    self.play_format ||= "singles"
    self.expires_at ||= DEFAULT_TTL.from_now
    self.message = message.to_s.strip.presence
  end

  def invitee_must_differ
    return if inviter_id.blank? || invitee_id.blank?
    return if inviter_id != invitee_id

    errors.add(:invitee, :cannot_invite_self)
  end

  def invitee_must_be_invitable
    return if invitee.blank? || inviter.blank?

    unless invitee.community_profile_eligible?
      errors.add(:invitee, :not_eligible)
      return
    end

    unless invitee.profile_visible_to?(inviter)
      errors.add(:invitee, :not_accessible)
      return
    end

    unless invitee.accepts_match_invitations?
      errors.add(:invitee, :opted_out)
    end
  end

  def no_duplicate_pending
    return if inviter_id.blank? || invitee_id.blank?

    if self.class.pending.where(inviter_id: inviter_id, invitee_id: invitee_id).exists?
      errors.add(:base, :duplicate_pending)
    end
  end

  def transition!(by:, to:, role:)
    raise ArgumentError, "unauthorized" unless authorized_actor?(by, role)

    with_lock do
      reload
      expire_if_needed_locked!
      raise ArgumentError, "not_pending" unless pending?

      yield if block_given?
      self.status = to
      self.responded_at = Time.current
      save!
    end
    self
  end

  def authorized_actor?(user, role)
    case role
    when :invitee then user&.id == invitee_id
    when :inviter then user&.id == inviter_id
    else false
    end
  end

  def expire_if_needed_locked!
    return unless pending? && expired_by_time?

    update!(status: "expired", responded_at: Time.current)
  end

  # Accepting an invitation that already includes a future proposed_at is explicit
  # agreement to that time (and optional court). Missing/past times leave the
  # invitation accepted but in scheduling-needed state — no invented Game.
  def finalize_accept_scheduling!
    if schedulable_on_accept?
      create_peer_game!
      self.scheduling_status = "scheduled"
      self.proposed_by = inviter if proposed_by_id.blank?
      self.proposal_updated_at ||= Time.current
    else
      self.scheduling_status = "needed"
    end
  end

  def schedulable_on_accept?
    proposed_at.present? && proposed_at > Time.current
  end

  def create_peer_game!
    return if game_id.present?

    created = Game.create!(
      user: inviter,
      date: proposed_at.to_date,
      time: proposed_at.strftime("%H:%M"),
      court_id: court_id,
      kind: "game",
      players_count: players_count_for_format,
      comment: [ message, proposal_note ].compact_blank.join(" — ").presence,
      sport: "Tennis",
      invite_only: true
    )

    [ inviter, invitee ].each do |user|
      created.participations.find_or_create_by!(user: user) do |participation|
        participation.status = "approved"
        participation.approved_at = Time.current
      end
    end

    self.game = created
  end

  def parse_proposed_at!(value)
    raise ArgumentError, "invalid_time" if value.blank?

    time = value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? value : Time.zone.parse(value.to_s)
    raise ArgumentError, "invalid_time" if time.blank?

    time
  rescue ArgumentError, TypeError
    raise ArgumentError, "invalid_time"
  end

  def resolve_court!(court_id)
    return nil if court_id.blank?

    court = Court.visible_to(inviter).find_by(id: court_id) || Court.visible_to(invitee).find_by(id: court_id)
    raise ArgumentError, "invalid_court" unless court

    court
  end

  def same_proposal_timestamp?(raw)
    return false if proposal_updated_at.blank? || raw.blank?

    got = Time.zone.parse(raw.to_s)
    return false if got.blank?

    # Compare to microsecond precision so same-second edits still invalidate tokens.
    proposal_updated_at.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N") == got.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N")
  rescue ArgumentError, TypeError
    false
  end
end
