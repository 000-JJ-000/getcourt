require "test_helper"

class GameInviteOnlyAccessTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "gio-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner", profile_visibility: "members")
    @peer = User.create!(email: "gio-peer-#{SecureRandom.hex(4)}@example.com", name: "Peer", profile_visibility: "members")
    @stranger = User.create!(email: "gio-str-#{SecureRandom.hex(4)}@example.com", name: "Stranger", profile_visibility: "members")
    @game = Game.create!(user: @owner, date: Date.tomorrow, time: "10:00", kind: "game", players_count: 2, invite_only: true)
    @game.participations.create!(user: @owner, status: "approved", approved_at: Time.current)
    @game.participations.create!(user: @peer, status: "approved", approved_at: Time.current)
  end

  test "invite_only visibility is limited to participants" do
    assert @game.visible_to?(@owner)
    assert @game.visible_to?(@peer)
    assert_not @game.visible_to?(@stranger)
    assert_not @game.visible_to?(nil)
    assert_not Game.publicly_visible.exists?(id: @game.id)
  end

  test "pending recruit can view invite_only game" do
    recruit = User.create!(email: "gio-rec-#{SecureRandom.hex(4)}@example.com", name: "Recruit", profile_visibility: "members")
    @game.participations.create!(user: recruit, status: "pending")
    assert @game.visible_to?(recruit)
  end

  test "peer cancel is idempotent and blocks results" do
    @game.cancel_peer_match!(by: @peer)
    assert @game.reload.canceled?
    assert_not @game.accepts_results?

    assert_nothing_raised { @game.cancel_peer_match!(by: @owner) }
    assert_raises(ArgumentError) { @game.cancel_peer_match!(by: @stranger) }
  end

  test "public games remain visible without auth" do
    open_game = Game.create!(user: @owner, date: Date.tomorrow, time: "11:00", kind: "game", invite_only: false)
    assert open_game.visible_to?(nil)
    assert open_game.visible_to?(@stranger)
  end
end
