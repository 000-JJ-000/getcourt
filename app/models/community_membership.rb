class CommunityMembership < ApplicationRecord
  ROLES = %w[owner moderator member].freeze
  STATUSES = %w[active pending removed].freeze

  belongs_to :community, inverse_of: :memberships
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :community_id }

  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :owners, -> { where(role: "owner") }
  scope :moderators, -> { where(role: "moderator") }

  def active?
    status == "active"
  end

  def pending?
    status == "pending"
  end

  def removed?
    status == "removed"
  end

  def owner?
    role == "owner"
  end

  def moderator_role?
    role == "moderator"
  end
end
