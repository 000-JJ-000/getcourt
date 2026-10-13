require "test_helper"

class CommunitiesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @email = "com-ctrl-#{SecureRandom.hex(4)}@example.com"
    sign_in_as(@email)
    @user = User.find_by!(email: @email)
    @user.update!(name: "Comm User", profile_visibility: "members")
  end

  test "requires auth for directory" do
    delete sign_out_url
    get communities_url
    assert_redirected_to new_session_path
  end

  test "creates joins and links game without exposing invite_only" do
    post communities_url, params: {
      community: { name: "City Hit", city_name: "Berlin", visibility: "public", membership_policy: "open", play_focus: "singles" }
    }
    community = Community.order(:id).last
    assert_redirected_to community_path(community)
    assert community.owner?(@user)

    other_email = "com-other-#{SecureRandom.hex(4)}@example.com"
    delete sign_out_url
    sign_in_as(other_email)
    other = User.find_by!(email: other_email)
    other.update!(profile_visibility: "members")

    post community_memberships_url(community)
    assert community.reload.active_member?(other)

    game = Game.create!(user: other, date: Date.tomorrow, time: "18:00", kind: "game", invite_only: false)
    post community_games_url(community), params: { game_id: game.id }
    assert_equal community.id, game.reload.community_id

    peer = Game.create!(user: other, date: Date.tomorrow, time: "19:00", kind: "game", invite_only: true)
    post community_games_url(community), params: { game_id: peer.id }
    assert_nil peer.reload.community_id
  end

  test "private community url alone does not grant access" do
    community = Community.create!(name: "Private Hit", creator: @user, visibility: "private")
    community.memberships.create!(user: @user, role: "owner", status: "active")

    stranger_email = "com-str-#{SecureRandom.hex(4)}@example.com"
    delete sign_out_url
    sign_in_as(stranger_email)
    get community_url(community)
    assert_response :not_found

    post community_memberships_url(community)
    assert_redirected_to community_path(community)
    follow_redirect!
    assert_response :not_found
    assert_not community.reload.active_member?(User.find_by!(email: stranger_email))
  end

  test "owner invites private member who accepts and creates community game" do
    community = Community.create!(name: "Invite Only Hit", creator: @user, visibility: "private")
    community.memberships.create!(user: @user, role: "owner", status: "active")

    invitee_email = "com-inv-#{SecureRandom.hex(4)}@example.com"
    delete sign_out_url
    sign_in_as(invitee_email)
    invitee = User.find_by!(email: invitee_email)
    invitee.update!(name: "Invitee", profile_visibility: "members")

    delete sign_out_url
    sign_in_as(@email)
    assert_enqueued_with(job: CommunityNotifyJob) do
      post invite_community_url(community), params: { user_id: invitee.id }
    end
    invitation = community.invitations.pending.find_by!(invitee: invitee)
    assert_redirected_to community_path(community)

    delete sign_out_url
    sign_in_as(invitee_email)
    post accept_community_invitation_url(invitation)
    assert community.reload.active_member?(invitee)

    get new_community_game_url(community)
    assert_redirected_to new_game_path(community_id: community.to_param)

    post games_url, params: {
      community_id: community.to_param,
      game: { date: Date.tomorrow, time: "18:00", kind: "game", players_count: 4 }
    }
    game = Game.order(:id).last
    assert_equal community.id, game.community_id
    assert_not game.invite_only?
  end
end
