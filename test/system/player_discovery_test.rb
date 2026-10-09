require "application_system_test_case"

class PlayerDiscoveryTest < ApplicationSystemTestCase
  test "signed-in member finds another player through filters" do
    viewer = User.create!(email: "sys-dir-viewer-#{SecureRandom.hex(4)}@example.com", name: "Sys Viewer", city_name: "Yekaterinburg")
    target = User.create!(
      email: "sys-dir-target-#{SecureRandom.hex(4)}@example.com",
      name: "Sys Target",
      city_name: "Yekaterinburg",
      ntrp_rating: 3.0,
      play_formats: %w[singles],
      play_styles: %w[casual],
      profile_visibility: "members"
    )
    User.create!(
      email: "sys-dir-other-#{SecureRandom.hex(4)}@example.com",
      name: "Sys Other",
      city_name: "Moscow",
      ntrp_rating: 5.5,
      play_formats: %w[doubles],
      play_styles: %w[competitive],
      profile_visibility: "public"
    )

    system_sign_in(viewer)
    visit players_path
    select "2.5", from: "Min NTRP"
    select "3.5", from: "Max NTRP"
    select "Singles", from: "Format"
    click_on "Search"

    assert_text "Sys Target"
    assert_no_text "Sys Other"
    assert_no_text target.email

    visit user_path(target)
    assert_current_path user_path(target)
    assert_text "Sys Target"
  end
end
