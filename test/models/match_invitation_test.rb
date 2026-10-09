require "test_helper"

class MatchInvitationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @inviter = User.create!(email: "mi-inviter-#{SecureRandom.hex(4)}@example.com", name: "Inviter", profile_visibility: "members")
    @invitee = User.create!(email: "mi-invitee-#{SecureRandom.hex(4)}@example.com", name: "Invitee", profile_visibility: "members")
  end

  test "creates pending invitation with defaults" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles", message: "Hit?")

    assert_equal "pending", invitation.status
    assert_equal "none", invitation.scheduling_status
    assert invitation.expires_at > 6.days.from_now
    assert_equal "Hit?", invitation.message
  end

  test "rejects self invite private invitee opt-out and duplicates" do
    assert_not MatchInvitation.new(inviter: @inviter, invitee: @inviter).valid?

    @invitee.update!(profile_visibility: "private")
    assert_not MatchInvitation.new(inviter: @inviter, invitee: @invitee).valid?

    @invitee.update!(profile_visibility: "members", accepts_match_invitations: false)
    assert_not MatchInvitation.new(inviter: @inviter, invitee: @invitee).valid?

    @invitee.update!(accepts_match_invitations: true)
    MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "doubles")
    assert_not MatchInvitation.new(inviter: @inviter, invitee: @invitee, play_format: "singles").valid?
  end

  test "accept without proposed_at needs scheduling and creates no game" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")

    invitation.accept!(by: @invitee)
    invitation.reload

    assert_equal "accepted", invitation.status
    assert_equal "needed", invitation.scheduling_status
    assert_nil invitation.game_id
  end

  test "accept with past proposed_at needs scheduling" do
    invitation = MatchInvitation.create!(
      inviter: @inviter,
      invitee: @invitee,
      play_format: "singles",
      proposed_at: 1.hour.ago
    )

    invitation.accept!(by: @invitee)
    invitation.reload

    assert_equal "accepted", invitation.status
    assert_equal "needed", invitation.scheduling_status
    assert_nil invitation.game_id
  end

  test "accept with future proposed_at creates invite-only singles game" do
    invitation = MatchInvitation.create!(
      inviter: @inviter,
      invitee: @invitee,
      play_format: "singles",
      proposed_at: 2.days.from_now.change(sec: 0)
    )

    invitation.accept!(by: @invitee)
    invitation.reload

    assert_equal "accepted", invitation.status
    assert_equal "scheduled", invitation.scheduling_status
    assert invitation.game.present?
    assert invitation.game.invite_only?
    assert_equal 2, invitation.game.players_count
    assert_equal 0, invitation.game.spots_left
    assert_equal [ @inviter.id, @invitee.id ].sort, invitation.game.participations.approved.pluck(:user_id).sort
    assert_not Game.publicly_visible.exists?(id: invitation.game.id)
  end

  test "doubles scheduled game leaves two open slots" do
    invitation = MatchInvitation.create!(
      inviter: @inviter,
      invitee: @invitee,
      play_format: "doubles",
      proposed_at: 3.days.from_now.change(sec: 0)
    )

    invitation.accept!(by: @invitee)
    invitation.reload

    assert_equal 4, invitation.game.players_count
    assert_equal 2, invitation.open_doubles_slots
  end

  test "propose and confirm creates exactly one game" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)

    court = courts(:one)
    court.update!(moderation_status: "approved") if court.respond_to?(:moderation_status)

    invitation.propose_schedule!(
      by: @inviter,
      proposed_at: 4.days.from_now.change(min: 0, sec: 0),
      court_id: court.id,
      note: "Bring balls"
    )
    invitation.reload

    assert_equal "proposed", invitation.scheduling_status
    assert_equal @inviter.id, invitation.proposed_by_id
    assert_equal "Bring balls", invitation.proposal_note

    invitation.confirm_schedule!(by: @invitee, proposal_updated_at: invitation.proposal_updated_at.iso8601(6))
    invitation.reload

    assert_equal "scheduled", invitation.scheduling_status
    assert_equal 1, Game.where(id: invitation.game_id).count
    assert invitation.game.invite_only?
    assert_equal court.id, invitation.game.court_id
  end

  test "changing proposal requires reconfirmation and rejects stale token" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)

    invitation.propose_schedule!(by: @inviter, proposed_at: 5.days.from_now.change(min: 0, sec: 0))
    stale = invitation.reload.proposal_updated_at.iso8601(6)
    travel 1.second

    invitation.propose_schedule!(by: @invitee, proposed_at: 6.days.from_now.change(min: 0, sec: 0), note: "Later")
    invitation.reload

    error = assert_raises(ArgumentError) { invitation.confirm_schedule!(by: @inviter, proposal_updated_at: stale) }
    assert_equal "stale_proposal", error.message
    assert_equal "proposed", invitation.reload.scheduling_status
    assert_nil invitation.game_id

    invitation.confirm_schedule!(by: @inviter, proposal_updated_at: invitation.proposal_updated_at.iso8601(6))
    assert invitation.reload.game.present?
  end

  test "proposer cannot confirm own proposal; stranger cannot propose" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)
    invitation.propose_schedule!(by: @inviter, proposed_at: 2.days.from_now.change(min: 0, sec: 0))

    assert_raises(ArgumentError) do
      invitation.confirm_schedule!(by: @inviter, proposal_updated_at: invitation.proposal_updated_at.iso8601(6))
    end

    stranger = User.create!(email: "mi-stranger-#{SecureRandom.hex(4)}@example.com", name: "X", profile_visibility: "members")
    assert_raises(ArgumentError) do
      invitation.propose_schedule!(by: stranger, proposed_at: 3.days.from_now.change(min: 0, sec: 0))
    end
  end

  test "rejects past proposals invalid courts and post-schedule proposes" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)

    assert_raises(ArgumentError) { invitation.propose_schedule!(by: @inviter, proposed_at: 1.hour.ago) }
    assert_raises(ArgumentError) { invitation.propose_schedule!(by: @inviter, proposed_at: 2.days.from_now, court_id: 0) }

    invitation.propose_schedule!(by: @inviter, proposed_at: 2.days.from_now.change(min: 0, sec: 0))
    invitation.confirm_schedule!(by: @invitee, proposal_updated_at: invitation.reload.proposal_updated_at.iso8601(6))

    assert_raises(ArgumentError) do
      invitation.propose_schedule!(by: @invitee, proposed_at: 3.days.from_now.change(min: 0, sec: 0))
    end
  end

  test "duplicate confirm is idempotent with single game" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)
    invitation.propose_schedule!(by: @inviter, proposed_at: 2.days.from_now.change(min: 0, sec: 0))
    token = invitation.reload.proposal_updated_at.iso8601(6)

    invitation.confirm_schedule!(by: @invitee, proposal_updated_at: token)
    game_id = invitation.reload.game_id

    assert_raises(ArgumentError) { invitation.confirm_schedule!(by: @invitee, proposal_updated_at: token) }
    assert_equal game_id, invitation.reload.game_id
    assert_equal 1, Game.where(id: game_id).count
  end

  test "concurrent confirmations create at most one game" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)
    invitation.propose_schedule!(by: @inviter, proposed_at: 2.days.from_now.change(min: 0, sec: 0))
    token = invitation.reload.proposal_updated_at.iso8601(6)

    errors = []
    threads = 2.times.map do
      Thread.new do
        MatchInvitation.find(invitation.id).confirm_schedule!(by: @invitee, proposal_updated_at: token)
      rescue ArgumentError => e
        errors << e.message
      end
    end
    threads.each(&:join)

    invitation.reload
    assert_equal "scheduled", invitation.scheduling_status
    assert_equal 1, Game.where(id: invitation.game_id).count
    assert_operator errors.count { |msg| msg == "already_scheduled" }, :<=, 1
    assert_empty(errors - [ "already_scheduled" ])
  end

  test "accepted invitations do not expire with pending ttl" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)
    invitation.update_columns(expires_at: 1.hour.ago)

    invitation.expire_if_needed!
    assert_equal "accepted", invitation.reload.status
    assert_equal "needed", invitation.scheduling_status
  end

  test "expire job only touches pending expired" do
    pending = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles", expires_at: 1.minute.ago)
    accepted = MatchInvitation.create!(
      inviter: @inviter,
      invitee: User.create!(email: "mi-acc-#{SecureRandom.hex(4)}@example.com", name: "A", profile_visibility: "members"),
      play_format: "singles"
    )
    accepted.accept!(by: accepted.invitee)
    accepted.update_columns(expires_at: 1.minute.ago)

    ExpireMatchInvitationsJob.perform_now

    assert_equal "expired", pending.reload.status
    assert_equal "accepted", accepted.reload.status
  end

  test "scheduling reminder marks once and enqueues notify" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    invitation.accept!(by: @invitee)
    invitation.update_columns(responded_at: 3.days.ago, scheduling_reminded_at: nil)

    assert_enqueued_with(job: MatchInvitationNotifyJob, args: [ invitation.id, "scheduling_reminder" ]) do
      MatchInvitationSchedulingReminderJob.perform_now
    end
    assert invitation.reload.scheduling_reminded_at.present?

    assert_no_enqueued_jobs(only: MatchInvitationNotifyJob) do
      MatchInvitationSchedulingReminderJob.perform_now
    end
  end

  test "concurrent accept and decline leave a single terminal state" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")

    errors = []
    t1 = Thread.new do
      invitation.accept!(by: @invitee)
    rescue ArgumentError => e
      errors << e.message
    end
    t2 = Thread.new do
      other = MatchInvitation.find(invitation.id)
      other.decline!(by: @invitee)
    rescue ArgumentError => e
      errors << e.message
    end
    [ t1, t2 ].each(&:join)

    invitation.reload
    assert_includes %w[accepted declined], invitation.status
    assert_equal 1, errors.count { |msg| msg == "not_pending" }
  end

  test "only invited roles can transition" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")

    assert_raises(ArgumentError) { invitation.accept!(by: @inviter) }
    assert_raises(ArgumentError) { invitation.cancel!(by: @invitee) }

    invitation.cancel!(by: @inviter)
    assert_equal "canceled", invitation.reload.status
  end

  test "proposal note length is limited" do
    invitation = MatchInvitation.new(
      inviter: @inviter,
      invitee: @invitee,
      play_format: "singles",
      proposal_note: "x" * (MatchInvitation::PROPOSAL_NOTE_MAX + 1)
    )
    assert_not invitation.valid?
  end
end
