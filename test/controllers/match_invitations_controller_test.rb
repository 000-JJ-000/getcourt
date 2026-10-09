require "test_helper"

class MatchInvitationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @inviter_email = "mi-ctrl-inviter-#{SecureRandom.hex(4)}@example.com"
    @invitee_email = "mi-ctrl-invitee-#{SecureRandom.hex(4)}@example.com"
    sign_in_as(@inviter_email)
    @inviter = User.find_by!(email: @inviter_email)
    @inviter.update!(name: "Ctrl Inviter", profile_visibility: "members")
    @invitee = User.create!(email: @invitee_email, name: "Ctrl Invitee", profile_visibility: "members", accepts_match_invitations: true)
  end

  test "requires authentication to list invitations" do
    delete sign_out_url
    get invitations_url
    assert_redirected_to new_session_path
  end

  test "creates invitation and enqueues notification" do
    assert_enqueued_with(job: MatchInvitationNotifyJob) do
      post user_match_invitations_url(@invitee), params: {
        match_invitation: { play_format: "doubles", message: "Saturday?" }
      }
    end

    assert_redirected_to invitations_path
    invitation = MatchInvitation.last
    assert_equal @inviter, invitation.inviter
    assert_equal @invitee, invitation.invitee
    assert_equal "doubles", invitation.play_format
    assert_equal "Saturday?", invitation.message
  end

  test "cannot invite private opted-out or self" do
    @invitee.update!(profile_visibility: "private")
    get new_user_match_invitation_url(@invitee)
    assert_response :not_found

    @invitee.update!(profile_visibility: "members", accepts_match_invitations: false)
    post user_match_invitations_url(@invitee), params: { match_invitation: { play_format: "singles" } }
    assert_response :not_found

    post user_match_invitations_url(@inviter), params: { match_invitation: { play_format: "singles" } }
    assert_response :not_found
  end

  test "invitee accepts and declines; inviter cancels; strangers forbidden" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles", proposed_at: 3.days.from_now)

    stranger_email = "mi-stranger-#{SecureRandom.hex(4)}@example.com"
    delete sign_out_url
    sign_in_as(stranger_email)
    post accept_invitation_url(invitation)
    assert_response :forbidden

    delete sign_out_url
    sign_in_as(@invitee_email)
    post accept_invitation_url(invitation)
    assert_redirected_to game_path(invitation.reload.game)
    assert_equal "accepted", invitation.status

    invitation2 = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "doubles")
    post decline_invitation_url(invitation2)
    assert_equal "declined", invitation2.reload.status

    invitation3 = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    delete sign_out_url
    sign_in_as(@inviter_email)
    post cancel_invitation_url(invitation3)
    assert_equal "canceled", invitation3.reload.status
  end

  test "show is limited to participants and escapes message content" do
    invitation = MatchInvitation.create!(
      inviter: @inviter,
      invitee: @invitee,
      play_format: "singles",
      message: "<script>alert(1)</script>"
    )

    get invitation_url(invitation)
    assert_response :success
    assert_includes response.body, "&lt;script&gt;"
    assert_not_includes response.body, "<script>alert(1)</script>"

    delete sign_out_url
    sign_in_as("mi-other-#{SecureRandom.hex(4)}@example.com")
    get invitation_url(invitation)
    assert_response :forbidden
  end

  test "existing users search picker still works" do
    get search_users_url, params: { q: "Ctrl Invitee" }
    assert_response :success
    assert JSON.parse(response.body).any? { |row| row["id"] == @invitee.id }
  end

  test "pending sender limit is enforced" do
    MatchInvitation::PENDING_PER_SENDER_LIMIT.times do |i|
      other = User.create!(email: "mi-limit-#{i}-#{SecureRandom.hex(3)}@example.com", name: "L#{i}", profile_visibility: "public")
      MatchInvitation.create!(inviter: @inviter, invitee: other, play_format: "singles")
    end

    post user_match_invitations_url(@invitee), params: { match_invitation: { play_format: "singles" } }
    assert_response :too_many_requests
  end

  test "accept without time redirects to coordination; propose and confirm schedule" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")

    delete sign_out_url
    sign_in_as(@invitee_email)
    post accept_invitation_url(invitation)
    assert_redirected_to invitation_path(invitation)
    assert_equal "needed", invitation.reload.scheduling_status

    delete sign_out_url
    sign_in_as(@inviter_email)
    assert_enqueued_with(job: MatchInvitationNotifyJob) do
      post propose_invitation_url(invitation), params: {
        match_invitation: { proposed_at: 3.days.from_now.change(min: 0, sec: 0).strftime("%Y-%m-%dT%H:%M"), proposal_note: "Clay?" }
      }
    end
    assert_redirected_to invitation_path(invitation)
    assert_equal "proposed", invitation.reload.scheduling_status

    delete sign_out_url
    sign_in_as(@invitee_email)
    post confirm_invitation_url(invitation), params: { proposal_updated_at: invitation.proposal_updated_at.iso8601(6) }
    assert_redirected_to game_path(invitation.reload.game)
    assert invitation.game.invite_only?
  end

  test "stale confirm and confirm-own are rejected" do
    invitation = MatchInvitation.create!(inviter: @inviter, invitee: @invitee, play_format: "singles")
    delete sign_out_url
    sign_in_as(@invitee_email)
    post accept_invitation_url(invitation)

    delete sign_out_url
    sign_in_as(@inviter_email)
    post propose_invitation_url(invitation), params: {
      match_invitation: { proposed_at: 2.days.from_now.change(min: 0, sec: 0).strftime("%Y-%m-%dT%H:%M") }
    }
    stale = invitation.reload.proposal_updated_at.iso8601(6)
    travel 1.second
    post propose_invitation_url(invitation), params: {
      match_invitation: { proposed_at: 4.days.from_now.change(min: 0, sec: 0).strftime("%Y-%m-%dT%H:%M") }
    }

    delete sign_out_url
    sign_in_as(@invitee_email)
    post confirm_invitation_url(invitation), params: { proposal_updated_at: stale }
    assert_redirected_to invitation_path(invitation)
    assert_equal I18n.t("match_invitations.flash.stale_proposal"), flash[:alert]

    delete sign_out_url
    sign_in_as(@inviter_email)
    post confirm_invitation_url(invitation), params: { proposal_updated_at: invitation.reload.proposal_updated_at.iso8601(6) }
    assert_redirected_to invitation_path(invitation)
    assert_equal I18n.t("match_invitations.flash.cannot_confirm_own"), flash[:alert]
  end

  test "invite-only peer games stay off public index" do
    invitation = MatchInvitation.create!(
      inviter: @inviter,
      invitee: @invitee,
      play_format: "singles",
      proposed_at: 2.days.from_now
    )
    delete sign_out_url
    sign_in_as(@invitee_email)
    post accept_invitation_url(invitation)
    game = invitation.reload.game

    assert game.invite_only?
    assert_not Game.publicly_visible.exists?(id: game.id)

    get games_url, params: { my_games: 1 }
    follow_redirect! while response.redirect?
    assert_response :success
    assert_includes response.body, game_path(game)
  end
end
