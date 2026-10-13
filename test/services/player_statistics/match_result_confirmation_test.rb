require "test_helper"

class PlayerStatistics::MatchResultConfirmationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @a = User.create!(email: "mrc-a-#{SecureRandom.hex(4)}@example.com", name: "A", profile_visibility: "members")
    @b = User.create!(email: "mrc-b-#{SecureRandom.hex(4)}@example.com", name: "B", profile_visibility: "members")
    @game = Game.create!(
      user: @a, date: Date.yesterday, time: "10:00", kind: "game",
      players_count: 2, invite_only: true
    )
    [ @a, @b ].each { |u| @game.participations.create!(user: u, status: "approved", approved_at: Time.current) }
  end

  test "invite_only submit is pending and skips elo and competitive counters until confirm" do
    ps = @a.player_statistic || @a.create_player_statistic
    before_rating = ps.singles_rating
    before_wins = ps.singles_wins.to_i
    before_games = ps.singles_games.to_i

    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: @game, actor: @a, mode: "singles",
      team_a_ids: [ @a.id ], team_b_ids: [ @b.id ],
      result: :a, played_at: @game.date.to_time, score: "6-4 6-3"
    )

    row = Match.find_by!(user: @a, game: @game)
    assert row.result_pending?
    ps.reload
    assert_equal [ before_rating ], [ ps.singles_rating ]
    assert_equal before_wins, ps.singles_wins.to_i
    assert_equal before_games, ps.singles_games.to_i

    token = row.stats["result_updated_at"]
    PlayerStatistics::ConfirmMatchResultService.new(
      game: @game, group_id: row.match_group_id, by: @b, result_updated_at: token
    ).call

    assert Match.find_by!(user: @a, game: @game).result_confirmed?
    ps.reload
    assert ps.singles_rating.present?
    assert_equal before_wins + 1, ps.singles_wins.to_i
    assert_equal before_games + 1, ps.singles_games.to_i
  end

  test "disputed results do not credit competitive counters" do
    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: @game, actor: @a, mode: "singles",
      team_a_ids: [ @a.id ], team_b_ids: [ @b.id ],
      result: :a, played_at: @game.date.to_time, score: "6-0 6-1"
    )
    row = Match.find_by!(user: @a, game: @game)
    wins_before = (@a.player_statistic || @a.create_player_statistic).singles_wins.to_i

    PlayerStatistics::DisputeMatchResultService.new(
      game: @game, group_id: row.match_group_id, by: @b,
      result_updated_at: row.stats["result_updated_at"]
    ).call

    assert row.reload.result_disputed?
    assert_equal wins_before, @a.player_statistic.reload.singles_wins.to_i
  end

  test "submitter cannot confirm; stale token rejected; dispute works" do
    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: @game, actor: @a, mode: "singles",
      team_a_ids: [ @a.id ], team_b_ids: [ @b.id ],
      result: :a, played_at: @game.date.to_time, score: "6-1 6-2"
    )
    row = Match.find_by!(user: @a, game: @game)
    token = row.stats["result_updated_at"]

    assert_raises(ArgumentError) do
      PlayerStatistics::ConfirmMatchResultService.new(
        game: @game, group_id: row.match_group_id, by: @a, result_updated_at: token
      ).call
    end

    travel 1.second
    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: @game, actor: @a, mode: "singles",
      team_a_ids: [ @a.id ], team_b_ids: [ @b.id ],
      result: :a, played_at: @game.date.to_time, score: "7-5 6-4", force_new: false
    )
    new_row = Match.find_by!(user: @a, game: @game)

    assert_raises(ArgumentError) do
      PlayerStatistics::ConfirmMatchResultService.new(
        game: @game, group_id: new_row.match_group_id, by: @b, result_updated_at: token
      ).call
    end

    PlayerStatistics::DisputeMatchResultService.new(
      game: @game, group_id: new_row.match_group_id, by: @b,
      result_updated_at: new_row.stats["result_updated_at"], note: "Wrong score"
    ).call
    assert Match.find_by!(user: @a, game: @game).result_disputed?
  end

  test "canceled game rejects new results" do
    @game.cancel_peer_match!(by: @a)
    assert_raises(ArgumentError) do
      Telegram::Flows::StatsScore::MatchUpserter.call(
        game: @game, actor: @a, mode: "singles",
        team_a_ids: [ @a.id ], team_b_ids: [ @b.id ],
        result: :a, played_at: Time.current, score: "6-0 6-0"
      )
    end
  end

  test "open games auto-confirm for elo compatibility" do
    open_game = Game.create!(user: @a, date: Date.yesterday, time: "12:00", kind: "game", invite_only: false)
    [ @a, @b ].each { |u| open_game.participations.find_or_create_by!(user: u) { |p| p.status = "approved"; p.approved_at = Time.current } }

    Telegram::Flows::StatsScore::MatchUpserter.call(
      game: open_game, actor: @a, mode: "singles",
      team_a_ids: [ @a.id ], team_b_ids: [ @b.id ],
      result: :a, played_at: open_game.date.to_time, score: "6-4 6-2"
    )

    assert Match.find_by!(user: @a, game: open_game).result_confirmed?
  end

  test "pending peer hours stay off PlayerStatistic until confirm" do
    ps = @a.player_statistic || @a.create_player_statistic
    before_hours = ps.singles_hours.to_f

    PlayerStatistics::UpsertMatchForGameService.new(
      user: @a, game: @game, actor: @a, mode: "singles",
      outcome: "win", played_at: @game.date.to_time, opponent: @b,
      score: "6-3 6-2", hours: 1.5,
      stats: {
        "team_a_ids" => [ @a.id ], "team_b_ids" => [ @b.id ],
        "match_group_id" => SecureRandom.uuid
      }
    ).call

    row = Match.find_by!(user: @a, game: @game)
    assert row.result_pending?
    assert_equal 1.5, row.stats["hours"].to_f
    assert_equal before_hours, @a.player_statistic.reload.singles_hours.to_f

    PlayerStatistics::ConfirmMatchResultService.new(
      game: @game, group_id: row.match_group_id, by: @b,
      result_updated_at: row.stats["result_updated_at"]
    ).call

    assert_in_delta before_hours + 1.5, @a.player_statistic.reload.singles_hours.to_f, 0.001
  end

  test "notifier failures do not raise" do
    stub_singleton(NotificationDelivery, :deliver, ->(*) { raise "smtp down" }) do
      assert_nothing_raised { MatchResults::Notifier.peer_canceled(@game) }
    end
  end
end
