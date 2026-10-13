require "test_helper"

class MatchResultsAccessTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner_email = "mra-owner-#{SecureRandom.hex(4)}@example.com"
    @peer_email = "mra-peer-#{SecureRandom.hex(4)}@example.com"
    sign_in_as(@owner_email)
    @owner = User.find_by!(email: @owner_email)
    @owner.update!(name: "Owner", profile_visibility: "members")
    @peer = User.create!(email: @peer_email, name: "Peer", profile_visibility: "members")
    @game = Game.create!(
      user: @owner, date: Date.yesterday, time: "10:00", kind: "game",
      players_count: 2, invite_only: true
    )
    [ @owner, @peer ].each { |u| @game.participations.create!(user: u, status: "approved", approved_at: Time.current) }
  end

  test "stranger cannot view invite_only game via direct url" do
    delete sign_out_url
    sign_in_as("mra-str-#{SecureRandom.hex(4)}@example.com")
    get game_url(@game)
    assert_response :not_found
  end

  test "api excludes invite_only games" do
    get api_v1_game_url(@game)
    assert_response :not_found
  end

  test "participant can cancel peer match" do
    delete sign_out_url
    sign_in_as(@peer_email)
    assert_enqueued_with(job: MatchResultNotifyJob) do
      post cancel_peer_game_url(@game)
    end
    assert @game.reload.canceled?
  end

  test "match history is private to owner" do
    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: @game, actor: @owner, mode: "singles",
      team_a_ids: [ @owner.id ], team_b_ids: [ @peer.id ],
      result: :a, played_at: @game.date.to_time, score: "6-3 6-3"
    )

    get match_history_url
    assert_response :success
    assert_includes response.body, "6-3 6-3"

    delete sign_out_url
    get match_history_url
    assert_redirected_to new_session_path
  end
end
