require "test_helper"

class CommunityInvitationTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "ci-own-#{SecureRandom.hex(4)}@example.com", name: "Owner", profile_visibility: "members")
    @invitee = User.create!(email: "ci-inv-#{SecureRandom.hex(4)}@example.com", name: "Invitee", profile_visibility: "members")
    @community = Community.create!(name: "Private Club", creator: @owner, visibility: "private")
    @community.memberships.create!(user: @owner, role: "owner", status: "active")
  end

  test "accept expires revoke and rejects duplicates" do
    invitation = @community.invitations.create!(inviter: @owner, invitee: @invitee)
    assert invitation.pending?

    dup = @community.invitations.build(inviter: @owner, invitee: @invitee)
    assert_not dup.valid?

    invitation.accept!(by: @invitee)
    assert_equal "accepted", invitation.reload.status
    assert @community.active_member?(@invitee)

    invitation2 = @community.invitations.create!(
      inviter: @owner,
      invitee: User.create!(email: "ci-2-#{SecureRandom.hex(4)}@example.com", name: "Two", profile_visibility: "members")
    )
    invitation2.revoke!(by: @owner)
    assert_equal "revoked", invitation2.reload.status

    expired = @community.invitations.create!(
      inviter: @owner,
      invitee: User.create!(email: "ci-3-#{SecureRandom.hex(4)}@example.com", name: "Three", profile_visibility: "members"),
      expires_at: 1.day.ago
    )
    expired.expire_if_needed!
    assert_equal "expired", expired.reload.status
  end

  test "only invitee may accept" do
    invitation = @community.invitations.create!(inviter: @owner, invitee: @invitee)
    assert_raises(ArgumentError) { invitation.accept!(by: @owner) }
  end
end
