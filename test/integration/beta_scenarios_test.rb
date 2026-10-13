require "test_helper"

# Repeatable multi-user scenarios for beta readiness (P1-07 §5).
class BetaScenariosTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "scenario A singles invite schedule result confirm history" do
    a_email = "beta-a-#{SecureRandom.hex(4)}@example.com"
    b_email = "beta-b-#{SecureRandom.hex(4)}@example.com"
    sign_in_as(a_email)
    a = User.find_by!(email: a_email)
    a.update!(name: "Player A", profile_visibility: "members", ntrp_rating: 3.5, play_formats: [ "singles" ])

    delete sign_out_url
    sign_in_as(b_email)
    b = User.find_by!(email: b_email)
    b.update!(name: "Player B", profile_visibility: "members", ntrp_rating: 3.5, play_formats: [ "singles" ])

    delete sign_out_url
    sign_in_as(a_email)
    get players_url
    assert_response :success
    assert_includes response.body, "Player B"

    post user_match_invitations_url(b), params: { match_invitation: { play_format: "singles", message: "Hit?" } }
    invitation = MatchInvitation.order(:id).last
    assert_equal a.id, invitation.inviter_id

    delete sign_out_url
    sign_in_as(b_email)
    post accept_invitation_url(invitation)
    invitation.reload
    assert_equal "accepted", invitation.status

    # Direct peer game + confirmed result (scheduling UI varies by court availability).
    game = Game.create!(user: a, date: Date.yesterday, time: "10:00", kind: "game", players_count: 2, invite_only: true)
    [ a, b ].each { |u| game.participations.create!(user: u, status: "approved", approved_at: Time.current) }

    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: game, actor: a, mode: "singles",
      team_a_ids: [ a.id ], team_b_ids: [ b.id ],
      result: :a, played_at: game.date.to_time, score: "6-4 6-3"
    )
    row = Match.find_by!(user: a, game: game)
    PlayerStatistics::ConfirmMatchResultService.new(
      game: game, group_id: row.match_group_id, by: b, result_updated_at: row.stats["result_updated_at"]
    ).call

    assert row.reload.result_confirmed?
    get match_history_url
    assert_response :success
  end

  test "scenario B doubles capacity and confirmed participants" do
    host = User.create!(email: "beta-d0-#{SecureRandom.hex(4)}@example.com", name: "Host", profile_visibility: "members")
    p2 = User.create!(email: "beta-d1-#{SecureRandom.hex(4)}@example.com", name: "P2", profile_visibility: "members")
    p3 = User.create!(email: "beta-d2-#{SecureRandom.hex(4)}@example.com", name: "P3", profile_visibility: "members")
    p4 = User.create!(email: "beta-d3-#{SecureRandom.hex(4)}@example.com", name: "P4", profile_visibility: "members")
    game = Game.create!(user: host, date: Date.yesterday, time: "11:00", kind: "game", players_count: 4, invite_only: true)
    [ host, p2, p3, p4 ].each { |u| game.participations.create!(user: u, status: "approved", approved_at: Time.current) }
    assert_equal 4, game.participations.where(status: "approved").count

    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: game, actor: host, mode: "doubles",
      team_a_ids: [ host.id, p2.id ], team_b_ids: [ p3.id, p4.id ],
      result: :a, played_at: game.date.to_time, score: "6-3 6-4"
    )
    row = Match.find_by!(user: host, game: game)
    assert row.result_pending?
    before = host.player_statistic&.doubles_wins.to_i

    PlayerStatistics::ConfirmMatchResultService.new(
      game: game, group_id: row.match_group_id, by: p3, result_updated_at: row.stats["result_updated_at"]
    ).call
    assert_equal before + 1, host.player_statistic.reload.doubles_wins.to_i
  end

  test "scenario C community approval create game join board" do
    owner_email = "beta-c0-#{SecureRandom.hex(4)}@example.com"
    member_email = "beta-c1-#{SecureRandom.hex(4)}@example.com"
    sign_in_as(owner_email)
    owner = User.find_by!(email: owner_email)
    owner.update!(name: "Owner", profile_visibility: "members")

    post communities_url, params: {
      community: { name: "Beta Club", visibility: "public", membership_policy: "approval", play_focus: "both" }
    }
    community = Community.order(:id).last

    delete sign_out_url
    sign_in_as(member_email)
    member = User.find_by!(email: member_email)
    member.update!(name: "Member", profile_visibility: "members")
    post community_memberships_url(community)
    membership = community.memberships.find_by!(user: member)
    assert membership.pending?

    delete sign_out_url
    sign_in_as(owner_email)
    post approve_community_membership_url(community, membership)
    assert community.reload.active_member?(member)

    delete sign_out_url
    sign_in_as(member_email)
    post games_url, params: {
      community_id: community.to_param,
      game: { date: Date.tomorrow, time: "17:00", kind: "game", players_count: 4 }
    }
    game = Game.order(:id).last
    assert_equal community.id, game.community_id
    get community_url(community)
    assert_response :success
    assert_includes response.body, game_path(game)
  end

  test "scenario D privacy abuse guards" do
    owner = User.create!(email: "beta-p0-#{SecureRandom.hex(4)}@example.com", name: "Own", profile_visibility: "private")
    stranger = User.create!(email: "beta-p1-#{SecureRandom.hex(4)}@example.com", name: "Str", profile_visibility: "members")
    community = Community.create!(name: "Hidden", creator: owner, visibility: "private")
    community.memberships.create!(user: owner, role: "owner", status: "active")

    sign_in_as(stranger.email)
    get community_url(community)
    assert_response :not_found

    post invite_community_url(community), params: { user_id: stranger.id }
    assert_response :forbidden

    invitation = community.invitations.create!(
      inviter: owner,
      invitee: User.create!(email: "beta-p2-#{SecureRandom.hex(4)}@example.com", name: "Real", profile_visibility: "members")
    )
    post accept_community_invitation_url(invitation)
    assert_redirected_to community_invitations_path
    assert_equal "pending", invitation.reload.status
  end
end
