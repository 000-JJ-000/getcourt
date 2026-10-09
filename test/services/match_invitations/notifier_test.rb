require "test_helper"

class MatchInvitations::NotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "notification failure does not raise" do
    inviter = User.create!(email: "mi-note-a-#{SecureRandom.hex(4)}@example.com", name: "A", profile_visibility: "members")
    invitee = User.create!(email: "mi-note-b-#{SecureRandom.hex(4)}@example.com", name: "B", profile_visibility: "members")
    invitation = MatchInvitation.create!(inviter: inviter, invitee: invitee, play_format: "singles")

    stub_singleton(NotificationDelivery, :deliver, ->(*) { raise "smtp down" }) do
      assert_nothing_raised { MatchInvitations::Notifier.created(invitation) }
      assert_nothing_raised { MatchInvitations::Notifier.proposal_submitted(invitation) }
      assert_nothing_raised { MatchInvitations::Notifier.scheduled(invitation) }
    end
  end
end
