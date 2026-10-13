class CommunityInvitation < ApplicationRecord
  STATUSES = %w[pending accepted declined revoked expired].freeze
  DEFAULT_TTL = 14.days

  belongs_to :community
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"

  validates :status, inclusion: { in: STATUSES }
  validates :expires_at, presence: true
  validate :invitee_must_differ
  validate :no_duplicate_pending, on: :create
  validate :invitee_must_be_eligible, on: :create

  before_validation :assign_defaults, on: :create

  scope :pending, -> { where(status: "pending") }
  scope :for_invitee, ->(user) { where(invitee_id: user.id) }
  scope :pending_expired, -> { pending.where(expires_at: ..Time.current) }

  def pending?
    status == "pending"
  end

  def expired_by_time?
    expires_at.present? && expires_at <= Time.current
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
    raise ArgumentError, "unauthorized" unless by&.id == invitee_id

    with_lock do
      reload
      expire_if_needed_locked!
      raise ArgumentError, "not_pending" unless pending?

      CommunityMembership.transaction do
        membership = community.memberships.find_or_initialize_by(user_id: invitee_id)
        raise ArgumentError, "already_member" if membership.persisted? && membership.active?

        membership.assign_attributes(role: "member", status: "active", responded_at: Time.current)
        membership.save!
        update!(status: "accepted", responded_at: Time.current)
      end
    end
    self
  end

  def decline!(by:)
    raise ArgumentError, "unauthorized" unless by&.id == invitee_id

    transition_terminal!(by: by, to: "declined")
  end

  def revoke!(by:)
    raise ArgumentError, "unauthorized" unless community.can_manage?(by)

    transition_terminal!(by: by, to: "revoked")
  end

  private

  def assign_defaults
    self.status ||= "pending"
    self.expires_at ||= DEFAULT_TTL.from_now
  end

  def invitee_must_differ
    return if inviter_id.blank? || invitee_id.blank?
    return if inviter_id != invitee_id

    errors.add(:invitee, :invalid)
  end

  def no_duplicate_pending
    return if community_id.blank? || invitee_id.blank?
    return unless self.class.pending.where(community_id: community_id, invitee_id: invitee_id).exists?

    errors.add(:base, :duplicate_pending)
  end

  def invitee_must_be_eligible
    return if invitee.blank? || community.blank?

    unless invitee.community_profile_eligible?
      errors.add(:invitee, :not_eligible)
      return
    end

    membership = community.membership_for(invitee)
    return unless membership&.active? || membership&.pending?

    errors.add(:invitee, :already_member)
  end

  def transition_terminal!(by:, to:)
    with_lock do
      reload
      expire_if_needed_locked!
      raise ArgumentError, "not_pending" unless pending?

      update!(status: to, responded_at: Time.current)
    end
    self
  end

  def expire_if_needed_locked!
    return unless pending? && expired_by_time?

    update!(status: "expired", responded_at: Time.current)
  end
end
