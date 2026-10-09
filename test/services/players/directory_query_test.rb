require "test_helper"

class Players::DirectoryQueryTest < ActiveSupport::TestCase
  setup do
    @viewer = User.create!(email: "viewer-dir-#{SecureRandom.hex(4)}@example.com", name: "Viewer", city_name: "Yekaterinburg")
    @local = create_player!(name: "Ada Local", city_name: "Yekaterinburg", ntrp_rating: 3.5, play_formats: %w[singles], play_styles: %w[casual])
    @remote = create_player!(name: "Zoe Remote", city_name: "Moscow", ntrp_rating: 4.5, play_formats: %w[doubles], play_styles: %w[competitive])
  end

  test "excludes viewer private telegram-generated and incomplete accounts" do
    private_user = create_player!(name: "Hidden", profile_visibility: "private")
    bot = User.create!(
      email: "tg-#{SecureRandom.hex(4)}@telegram.getcourt",
      telegram_generated_email: true,
      name: "Bot",
      profile_visibility: "public"
    )

    ids = Players::DirectoryQuery.new(viewer: @viewer).relation.pluck(:id)

    assert_includes ids, @local.id
    assert_includes ids, @remote.id
    assert_not_includes ids, @viewer.id
    assert_not_includes ids, private_user.id
    assert_not_includes ids, bot.id
  end

  test "orders same city then completeness then name then id" do
    incomplete_local = create_player!(name: "Ben Bare", city_name: "Yekaterinburg")
    ids = Players::DirectoryQuery.new(viewer: @viewer).relation.pluck(:id)

    assert_operator ids.index(@local.id), :<, ids.index(incomplete_local.id)
    assert_operator ids.index(incomplete_local.id), :<, ids.index(@remote.id)
  end

  test "filters by city ntrp and preferences" do
    city = City.create!(
      name: "Yekaterinburg",
      asciiname: "Yekaterinburg",
      country_code: "RU",
      timezone: "Asia/Yekaterinburg",
      population: 1_000_000,
      geoname_id: 920_000_000 + SecureRandom.random_number(1_000_000)
    )
    @local.update!(city_id: city.id)

    query = Players::DirectoryQuery.new(
      viewer: @viewer,
      filters: {
        city_id: city.id,
        ntrp_min: "3.0",
        ntrp_max: "4.0",
        play_format: "singles",
        play_style: "casual"
      }
    )
    ids = query.relation.pluck(:id)

    assert_equal [ @local.id ], ids
  ensure
    @local.update_columns(city_id: nil)
    city&.destroy
  end

  test "combined filters and invalid inputs are ignored safely" do
    query = Players::DirectoryQuery.new(
      viewer: @viewer,
      filters: {
        ntrp_min: "nope",
        ntrp_max: "9.9",
        play_format: "triples",
        play_style: "intense"
      }
    )

    assert_empty query.applied_filters
    ids = query.relation.pluck(:id)
    assert_includes ids, @local.id
    assert_includes ids, @remote.id
  end

  test "swaps reversed ntrp bounds" do
    query = Players::DirectoryQuery.new(viewer: @viewer, filters: { ntrp_min: "5.0", ntrp_max: "3.0" })
    assert_equal "3.0", query.filters.ntrp_min.to_s("F")
    assert_equal "5.0", query.filters.ntrp_max.to_s("F")
  end

  private

  def create_player!(attrs)
    User.create!({
      email: "player-#{SecureRandom.hex(4)}@example.com",
      profile_visibility: "members",
      telegram_generated_email: false
    }.merge(attrs))
  end
end
