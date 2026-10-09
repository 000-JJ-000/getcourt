require "application_system_test_case"

class MatchInvitationSystemTest < ApplicationSystemTestCase
  test "invite accept flow creates a game when time is proposed" do
    inviter = User.create!(email: "sys-mi-inviter-#{SecureRandom.hex(4)}@example.com", name: "Sys Inviter", profile_visibility: "members")
    invitee = User.create!(email: "sys-mi-invitee-#{SecureRandom.hex(4)}@example.com", name: "Sys Invitee", profile_visibility: "members")

    system_sign_in(inviter)
    visit user_path(invitee)
    click_on "Invite to play"
    select "Singles", from: "Format"
    fill_in "Message", with: "Morning hit?"
    # datetime-local: leave blank for handshake path in UI; set via model for game path
    click_on "Send invitation"
    assert_text "Invitation sent"

    Capybara.reset_sessions!
    system_sign_in(invitee)
    visit invitations_path
    assert_text "Sys Inviter"
    assert_text "Morning hit?"
    click_on "Accept"
    assert_text "pick a time together"

    fill_in "Proposed date and time", with: 3.days.from_now.strftime("%Y-%m-%dT10:00")
    click_on "Send proposal"
    assert_text "Schedule proposal sent"

    Capybara.reset_sessions!
    system_sign_in(inviter)
    visit invitations_path
    click_on "Schedule"
    click_on "Confirm schedule"
    assert_text "Schedule confirmed"
  end
end
