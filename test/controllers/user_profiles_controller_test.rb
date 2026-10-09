require "test_helper"

class UserProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner_email = "profile-owner-#{SecureRandom.hex(4)}@example.com"
    sign_in_as(@owner_email)
    @owner = User.find_by!(email: @owner_email)
    @owner.update!(
      name: "Owner Player",
      city_name: "Yekaterinburg",
      ntrp_rating: 3.5,
      play_formats: %w[singles],
      play_styles: %w[casual],
      availability: { "mon" => %w[evening], "notes" => "After 6" },
      about_me: "Loves clay",
      profile_visibility: "public",
      show_stats_on_profile: true,
      show_telegram_on_profile: false,
      telegram_username: "owner_tg_nick"
    )
  end

  test "owner can update profile fields without mass-assigning protected attrs" do
    patch account_url, params: {
      section: "profile",
      user: {
        name: "Updated Name",
        ntrp_rating: "4.0",
        play_formats: %w[doubles],
        play_styles: %w[competitive],
        availability: { "tue" => %w[morning], "notes" => "Early" },
        profile_visibility: "members",
        show_stats_on_profile: "0",
        show_telegram_on_profile: "1",
        about_me: "Updated bio",
        admin: true,
        telegram_chat_id: 999_999
      }
    }

    @owner.reload
    assert_redirected_to profile_account_path
    assert_equal "Updated Name", @owner.name
    assert_equal BigDecimal("4.0"), @owner.ntrp_rating
    assert_equal %w[doubles], @owner.play_formats
    assert_equal %w[competitive], @owner.play_styles
    assert_equal({ "tue" => %w[morning], "notes" => "Early" }, @owner.availability)
    assert_equal "members", @owner.profile_visibility
    assert_not @owner.show_stats_on_profile?
    assert @owner.show_telegram_on_profile?
    assert_equal "Updated bio", @owner.about_me
    assert_not @owner.admin?
    assert_nil @owner.telegram_chat_id
  end

  test "public profile is visible anonymously without sensitive fields" do
    delete sign_out_url
    get user_url(@owner)

    assert_response :success
    assert_includes response.body, "Owner Player"
    assert_includes response.body, "Yekaterinburg"
    assert_includes response.body, "3.5"
    assert_includes response.body, "self-reported"
    assert_includes response.body, "Loves clay"
    assert_not_includes response.body, @owner.email
    assert_not_includes response.body, "@owner_tg_nick"
    assert_not_includes response.body, "999"
  end

  test "members profile requires authentication" do
    @owner.update!(profile_visibility: "members")
    delete sign_out_url

    get user_url(@owner)

    assert_redirected_to new_session_path
  end

  test "private profile is hidden from other members" do
    @owner.update!(profile_visibility: "private")
    delete sign_out_url
    sign_in_as("other-viewer-#{SecureRandom.hex(4)}@example.com")

    get user_url(@owner)

    assert_response :not_found
  end

  test "telegram-generated accounts are not shown to others" do
    bot = User.create!(
      email: "tg-#{SecureRandom.hex(4)}@telegram.getcourt",
      telegram_generated_email: true,
      name: "Bot Only",
      profile_visibility: "public"
    )
    delete sign_out_url

    get user_url(bot)

    assert_response :not_found
  ensure
    bot&.destroy
  end

  test "telegram handle appears only when opted in" do
    @owner.update!(show_telegram_on_profile: true, profile_visibility: "public")
    delete sign_out_url

    get user_url(@owner)

    assert_response :success
    assert_includes response.body, "@owner_tg_nick"
  end

  test "nonpublic profiles send noindex" do
    @owner.update!(profile_visibility: "members")
    get user_url(@owner)

    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex, follow"
  end

  test "picking a city also stores city_id" do
    city = City.create!(
      name: "Yekaterinburg",
      asciiname: "Yekaterinburg",
      country_code: "RU",
      timezone: "Asia/Yekaterinburg",
      population: 1_495_066,
      geoname_id: 910_000_000 + SecureRandom.random_number(1_000_000)
    )

    patch account_url, params: {
      section: "profile",
      selected_city_id: city.id,
      user: { name: @owner.name }
    }

    @owner.reload
    assert_equal city.id, @owner.city_id
    assert_equal "Yekaterinburg", @owner.city_name
  ensure
    @owner&.update_columns(city_id: nil)
    city&.destroy
  end
end
