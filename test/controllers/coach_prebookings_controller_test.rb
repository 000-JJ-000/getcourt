require "test_helper"

class CoachPrebookingsControllerTest < ActionDispatch::IntegrationTest
  test "accepted coach can confirm a date without taking a player slot" do
    coach = User.create!(email: "coach-booking-controller@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      with_coach: true,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted")
    sign_in_as(coach.email)

    assert_difference -> { game.coach_prebookings.count }, 1 do
      assert_no_difference -> { game.prebookings.count } do
        post game_coach_prebookings_url(game), params: { date: game.next_date }
      end
    end

    assert_redirected_to game_path(game, month: game.next_date.strftime("%Y-%m"))
  ensure
    coach&.destroy
  end

  test "a coach cannot cancel the other coach's confirmation" do
    first = User.create!(email: "booking-owner-coach@example.com", coach: true)
    second = User.create!(email: "booking-other-coach@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      kind: "training",
      with_coach: true,
      coach: first,
      second_coach: second,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted", second_coach_invitation_status: "accepted")
    booking = game.coach_prebookings.create!(coach: first, date: game.next_date)
    sign_in_as(second.email)

    assert_no_difference -> { game.coach_prebookings.count } do
      delete game_coach_prebooking_url(game, booking)
    end

    assert_response :not_found
  ensure
    first&.destroy
    second&.destroy
  end

  # Первое занятие серии закрыто для записи игроков, но тренеру его карточка
  # нужна: подтверждение на эту дату надо видеть и уметь снять.
  test "the first session keeps its card for the coach while player prebooking is closed" do
    coach = User.create!(email: "first-session-coach@example.com", coach: true)

    travel_to Time.zone.local(2026, 9, 12, 12, 0) do
      game = Game.create!(court: courts(:one), user: users(:one), kind: "training", with_coach: true, coach: coach,
                          recurring: true, prebooking_enabled: true, players_count: 2, date: Date.new(2026, 9, 15))
      game.update!(coach_invitation_status: "accepted")
      game.coach_prebookings.create!(coach: coach, date: Date.new(2026, 9, 15))

      assert game.prebooking_closed_on?(Date.new(2026, 9, 15))
      assert_equal [ Date.new(2026, 9, 15), Date.new(2026, 9, 22), Date.new(2026, 9, 29) ], game.prebooking_dates_in(Date.new(2026, 9, 1))

      sign_in_as(coach.email)
      get game_path(game)

      assert_select "article#prebooking-2026-09-15" do
        assert_select "[data-testid=prebooking-first-session]"
        assert_select "button", text: I18n.t("games.prebookings.coach_cancel")
        assert_select "button", text: I18n.t("games.prebookings.book"), count: 0
      end
      assert_select "article#prebooking-2026-09-22 button", text: I18n.t("games.prebookings.coach_cancel"), count: 0
    end
  ensure
    coach&.destroy
  end

  test "a coach cancels their own confirmation" do
    coach = User.create!(email: "booking-cancelling-coach@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      kind: "training",
      with_coach: true,
      coach: coach,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted")
    booking = game.coach_prebookings.create!(coach: coach, date: game.next_date)
    sign_in_as(coach.email)

    assert_difference -> { game.coach_prebookings.count }, -1 do
      delete game_coach_prebooking_url(game, booking)
    end

    assert_redirected_to game_path(game, month: booking.date.strftime("%Y-%m"))
  ensure
    coach&.destroy
  end

  test "coach sees their confirmation inside the day card" do
    coach = User.create!(email: "coach-calendar-card@example.com", coach: true, name: "Card Coach")
    # Серия по понедельникам; в сентябре с 8-го числа впереди 14, 21 и 28.
    travel_to Time.zone.local(2026, 9, 8, 12, 0) do
      game = Game.create!(
        court: courts(:one),
        user: users(:one),
        with_coach: true,
        coach: coach,
        recurring: true,
        date: Date.new(2026, 9, 7)
      )
      game.update!(coach_invitation_status: "accepted")
      game.coach_prebookings.create!(coach: coach, date: game.next_date)
      sign_in_as(coach.email)

      get more_game_prebookings_url(game, month: "2026-09")

      assert_response :success
      assert_select "[data-testid=?]", "prebooking-day", 3 do |cards|
        assert_match I18n.t("games.prebookings.coach_confirmed"), cards.first.to_s
        assert_match I18n.t("games.prebookings.coach_not_booked"), cards[1].to_s
      end
    end
  ensure
    coach&.destroy
  end
end
