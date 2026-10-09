require "application_system_test_case"

class PlayerProfileTest < ApplicationSystemTestCase
  test "owner edits profile and public visitors can view it" do
    email = "system-profile-#{SecureRandom.hex(4)}@example.com"
    user = User.create!(email: email)
    system_sign_in(user)

    visit profile_account_path
    fill_in "Name", with: "System Player"
    select "3.5", from: "NTRP rating"
    check "Singles"
    check "Casual"
    find("#user_availability_mon_evening").check
    select "Public", from: "Who can see your profile"
    fill_in "About me", with: "Ready for hit sessions"
    click_on "Save Changes"

    assert_text "Account updated"
    user.reload
    assert_equal "System Player", user.name
    assert_equal BigDecimal("3.5"), user.ntrp_rating
    assert_includes user.play_formats, "singles"
    assert_equal "public", user.profile_visibility

    Capybara.reset_sessions!
    visit user_path(user)

    assert_text "System Player"
    assert_text "3.5"
    assert_text "Ready for hit sessions"
    assert_no_text email
  end
end
