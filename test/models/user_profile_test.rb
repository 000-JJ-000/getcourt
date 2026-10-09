require "test_helper"

class UserProfileTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "profile-model-#{SecureRandom.hex(4)}@example.com", name: "Pat Player")
  end

  test "defaults keep existing accounts member-visible with stats on and telegram off" do
    assert_equal "members", @user.profile_visibility
    assert @user.show_stats_on_profile?
    assert_not @user.show_telegram_on_profile?
    assert_equal [], @user.play_formats
    assert_equal [], @user.play_styles
    assert_equal({}, @user.availability)
    assert_nil @user.ntrp_rating
  end

  test "accepts self-reported ntrp half-steps and unset" do
    @user.ntrp_rating = 3.5
    assert @user.valid?

    @user.ntrp_rating = nil
    assert @user.valid?

    @user.ntrp_rating = 3.2
    assert_not @user.valid?
    assert @user.errors[:ntrp_rating].any?
  end

  test "rejects invalid play formats styles and availability" do
    @user.play_formats = [ "triples" ]
    assert_not @user.valid?

    @user.reload
    @user.play_styles = [ "intense" ]
    assert_not @user.valid?

    @user.reload
    @user.availability = { "monday" => [ "morning" ] }
    assert_not @user.valid?

    @user.reload
    @user.availability = { "mon" => [ "late" ] }
    assert_not @user.valid?

    @user.reload
    @user.availability = { "notes" => "x" * (User::AVAILABILITY_NOTES_MAX + 1) }
    assert_not @user.valid?
  end

  test "accepts documented availability structure" do
    @user.availability = {
      "mon" => %w[morning evening],
      "sat" => %w[afternoon],
      "notes" => "After work"
    }
    @user.play_formats = %w[singles doubles]
    @user.play_styles = %w[casual]
    assert @user.valid?
  end

  test "profile visibility gates community eligibility" do
    viewer = User.create!(email: "viewer-#{SecureRandom.hex(4)}@example.com")
    assert @user.profile_visible_to?(viewer)

    @user.update!(profile_visibility: "private")
    assert @user.profile_visible_to?(@user)
    assert_not @user.profile_visible_to?(viewer)
    assert_not @user.profile_visible_to?(nil)

    @user.update!(profile_visibility: "public")
    assert @user.profile_visible_to?(nil)

    bot = User.create!(
      email: "tg-#{SecureRandom.hex(4)}@telegram.getcourt",
      telegram_generated_email: true,
      profile_visibility: "public"
    )
    assert_not bot.community_profile_eligible?
    assert_not bot.profile_visible_to?(viewer)
    assert bot.profile_visible_to?(bot)
  end

  test "does not rewrite legacy skill levels when profile fields change" do
    sport = User::SPORTS.first
    @user.update!(skill_levels: { sport => "intermediate" }, skill_level: "advanced")
    @user.update!(ntrp_rating: 4.0, play_formats: [ "singles" ])

    @user.reload
    assert_equal "intermediate", @user.skill_levels[sport]
    assert_equal "advanced", @user.skill_level
  end
end
