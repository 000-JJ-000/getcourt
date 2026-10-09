require "application_system_test_case"

# Календарь предзаписи листается внутри страницы, а бронь уходит обычной
# формой — и ответ на неё не должен возвращать календарь на месяц по умолчанию.
class PrebookingCalendarTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  test "booking in the next month keeps the calendar on that month" do
    owner = User.create!(email: "calendar_owner@example.com", name: "Calendar Owner")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current.next_occurring(:monday),
                        recurring: true, prebooking_enabled: true, players_count: 2)
    sign_in owner

    visit game_path(game)
    first_month = find("[data-testid=prebooking-month]").text
    find("[data-testid=prebooking-next-month]").click
    assert_no_selector "[data-testid=prebooking-month]", text: first_month
    next_month = find("[data-testid=prebooking-month]").text

    within("[data-testid=prebooking-day]", match: :first) { click_button "Book", match: :first }

    assert_selector "[data-testid=prebooking-day]", text: "Calendar Owner"
    assert_selector "[data-testid=prebooking-month]", text: next_month
  end

  private

  def sign_in(user)
    system_sign_in(user)
  end
end
