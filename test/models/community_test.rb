require "test_helper"

class CommunityTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "com-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner", profile_visibility: "members")
  end

  test "creates community with owner membership" do
    community = nil
    Community.transaction do
      community = Community.create!(name: "Morning Hitters", creator: @owner, city_name: "Madrid", visibility: "public")
      community.memberships.create!(user: @owner, role: "owner", status: "active", responded_at: Time.current)
    end

    assert community.slug.present?
    assert community.owner?(@owner)
    assert_equal 1, community.member_count
  end

  test "directory excludes private communities" do
    Community.create!(name: "Public Club", creator: @owner, visibility: "public").tap do |c|
      c.memberships.create!(user: @owner, role: "owner", status: "active")
    end
    Community.create!(name: "Secret Club", creator: @owner, visibility: "private").tap do |c|
      c.memberships.create!(user: @owner, role: "owner", status: "active")
    end

    relation = Communities::DirectoryQuery.new(viewer: @owner, filters: {}).relation
    names = relation.pluck(:name)
    assert_includes names, "Public Club"
    assert_not_includes names, "Secret Club"
  end

  test "membership join approve leave and sole owner protection" do
    community = Community.create!(name: "Approval Club", creator: @owner, visibility: "public", membership_policy: "approval")
    community.memberships.create!(user: @owner, role: "owner", status: "active")
    joiner = User.create!(email: "com-join-#{SecureRandom.hex(4)}@example.com", name: "Joiner", profile_visibility: "members")

    membership = Communities::MembershipService.new(community, actor: joiner).join_or_request!
    assert membership.pending?

    Communities::MembershipService.new(community, actor: @owner).approve!(membership)
    assert membership.reload.active?

    assert_raises(ArgumentError) do
      Communities::MembershipService.new(community, actor: @owner).leave!
    end

    Communities::MembershipService.new(community, actor: joiner).leave!
    assert membership.reload.removed?
  end
end
