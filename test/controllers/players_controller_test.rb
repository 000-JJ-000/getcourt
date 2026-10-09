require "test_helper"

class PlayersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @viewer_email = "players-viewer-#{SecureRandom.hex(4)}@example.com"
    sign_in_as(@viewer_email)
    @viewer = User.find_by!(email: @viewer_email)
    @viewer.update!(name: "Viewer", city_name: "Yekaterinburg")

    @visible = User.create!(
      email: "players-visible-#{SecureRandom.hex(4)}@example.com",
      name: "Visible Player",
      city_name: "Yekaterinburg",
      ntrp_rating: 3.5,
      play_formats: %w[singles],
      play_styles: %w[casual],
      availability: { "mon" => %w[evening] },
      profile_visibility: "members",
      telegram_username: "visible_tg_nick"
    )
    @private = User.create!(
      email: "players-private-#{SecureRandom.hex(4)}@example.com",
      name: "Private Player",
      city_name: "Yekaterinburg",
      profile_visibility: "private"
    )
  end

  test "requires authentication" do
    delete sign_out_url
    get players_url
    assert_redirected_to new_session_path
  end

  test "lists eligible players without private contact fields" do
    get players_url

    assert_response :success
    assert_includes response.body, "Visible Player"
    assert_includes response.body, "Yekaterinburg"
    assert_includes response.body, "3.5"
    assert_select "[data-testid=players-results] a[href=?]", user_path(@visible)
    results = css_select("[data-testid=players-results]").first.to_html
    assert_not_includes results, @visible.email
    assert_not_includes results, "@visible_tg_nick"
    assert_not_includes response.body, "Private Player"
    assert_select "meta[name=robots][content=?]", "noindex, follow"
  end

  test "filters by ntrp and preferences" do
    other = User.create!(
      email: "players-other-#{SecureRandom.hex(4)}@example.com",
      name: "Doubles Only",
      city_name: "Moscow",
      ntrp_rating: 5.0,
      play_formats: %w[doubles],
      play_styles: %w[competitive],
      profile_visibility: "public"
    )

    get players_url, params: { ntrp_min: "3.0", ntrp_max: "4.0", play_format: "singles", play_style: "casual" }

    assert_response :success
    assert_includes response.body, "Visible Player"
    assert_not_includes response.body, "Doubles Only"
  ensure
    other&.destroy
  end

  test "invalid filters do not error or leak private profiles" do
    get players_url, params: { ntrp_min: "bad", play_format: "triples", profile_visibility: "private" }

    assert_response :success
    assert_includes response.body, "Visible Player"
    assert_not_includes response.body, "Private Player"
  end

  test "paginates deterministically" do
    Players::DirectoryQuery::PAGE_SIZE.times do |i|
      User.create!(
        email: "page-player-#{i}-#{SecureRandom.hex(3)}@example.com",
        name: format("Page %02d", i),
        city_name: "Moscow",
        profile_visibility: "members"
      )
    end

    get players_url
    assert_response :success
    first_page_ids = css_select("[data-testid=players-results] a").map { |a| a["href"] }

    get players_url, params: { page: 2 }
    assert_response :success
    second_page_ids = css_select("[data-testid=players-results] a").map { |a| a["href"] }

    assert first_page_ids.any?
    assert second_page_ids.any?
    assert_empty first_page_ids & second_page_ids
  end

  test "avatar endpoint for listed member remains gated" do
    get avatar_user_url(@private)
    assert_response :not_found

    get avatar_user_url(@visible)
    # No attachment → not found; visibility still allows the action.
    assert_response :not_found
  end

  test "invitation picker search still works" do
    get search_users_url, params: { q: "Visible" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |row| row["id"] == @visible.id }
  end
end
