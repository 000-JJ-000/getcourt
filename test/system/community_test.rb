require "application_system_test_case"

class CommunitySystemTest < ApplicationSystemTestCase
  test "create and join a public community" do
    owner = User.create!(email: "sys-com-owner-#{SecureRandom.hex(4)}@example.com", name: "Sys Owner", profile_visibility: "members")
    member = User.create!(email: "sys-com-member-#{SecureRandom.hex(4)}@example.com", name: "Sys Member", profile_visibility: "members")

    system_sign_in(owner)
    visit communities_path
    click_on "Create a community"
    fill_in "Name", with: "Park Tennis"
    fill_in "City / area", with: "Berlin"
    click_on "Create"
    assert_text "Community created"
    assert_text "Park Tennis"

    Capybara.reset_sessions!
    system_sign_in(member)
    visit communities_path
    click_on "Park Tennis"
    click_on "Join"
    assert_text "You joined the community"
  end
end
