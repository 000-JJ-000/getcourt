class Community < ApplicationRecord
  VISIBILITIES = %w[public private].freeze
  MEMBERSHIP_POLICIES = %w[open approval].freeze
  PLAY_FOCUSES = %w[singles doubles both].freeze
  NAME_MAX = 80
  DESCRIPTION_MAX = 2000

  belongs_to :creator, class_name: "User"
  belongs_to :city, optional: true
  has_many :memberships, class_name: "CommunityMembership", dependent: :destroy, inverse_of: :community
  has_many :active_memberships, -> { active }, class_name: "CommunityMembership", inverse_of: :community
  has_many :members, through: :active_memberships, source: :user
  has_many :invitations, class_name: "CommunityInvitation", dependent: :destroy
  has_many :games, dependent: :nullify

  before_validation :normalize_fields
  before_validation :assign_slug, on: :create

  validates :name, presence: true, length: { maximum: NAME_MAX }
  validates :slug, presence: true, uniqueness: true
  validates :description, length: { maximum: DESCRIPTION_MAX }, allow_blank: true
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :membership_policy, inclusion: { in: MEMBERSHIP_POLICIES }
  validates :play_focus, inclusion: { in: PLAY_FOCUSES }, allow_blank: true
  validate :ntrp_range_valid

  scope :publicly_listed, -> { where(visibility: "public") }
  scope :ordered, -> { order(Arel.sql("LOWER(name) ASC"), :id) }

  def public?
    visibility == "public"
  end

  def private?
    visibility == "private"
  end

  def open_join?
    membership_policy == "open"
  end

  def approval_required?
    membership_policy == "approval"
  end

  def visible_to?(user)
    return true if public?
    return false if user.blank?
    return true if user.admin?
    return true if creator_id == user.id
    return true if memberships.active.exists?(user_id: user.id) || memberships.pending.exists?(user_id: user.id)
    return true if invitations.pending.where(invitee_id: user.id).exists?

    false
  end

  # Private communities are not browsable by URL alone — invitation or membership required.
  def teaser_accessible?(user)
    visible_to?(user)
  end

  def membership_for(user)
    return nil if user.blank?

    memberships.find_by(user_id: user.id)
  end

  def active_member?(user)
    return false if user.blank?

    memberships.active.exists?(user_id: user.id)
  end

  def owner?(user)
    return false if user.blank?

    memberships.active.owners.exists?(user_id: user.id) || (user.admin? && creator_id == user.id)
  end

  def moderator?(user)
    return false if user.blank?
    return true if owner?(user) || user.admin?

    memberships.active.moderators.exists?(user_id: user.id)
  end

  def can_manage?(user)
    moderator?(user)
  end

  def can_edit_settings?(user)
    owner?(user) || user&.admin?
  end

  def member_count
    if memberships.loaded?
      memberships.count(&:active?)
    else
      memberships.active.count
    end
  end

  def directory_blurb
    description.to_s.strip.truncate(160)
  end

  def to_param
    slug
  end

  private

  def normalize_fields
    self.name = name.to_s.strip.presence
    self.description = description.to_s.strip.presence
    self.city_name = city_name.to_s.strip.presence || city&.name
    self.play_focus = play_focus.to_s.strip.presence
  end

  def assign_slug
    return if slug.present? || name.blank?

    base = name.to_s.parameterize.presence || "community"
    candidate = base
    n = 2
    while self.class.where(slug: candidate).exists?
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end

  def ntrp_range_valid
    return if ntrp_min.blank? && ntrp_max.blank?
    return if ntrp_min.blank? || ntrp_max.blank?
    return if ntrp_min <= ntrp_max

    errors.add(:ntrp_max, :invalid)
  end
end
