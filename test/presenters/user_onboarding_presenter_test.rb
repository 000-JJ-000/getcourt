require "test_helper"

class UserOnboardingPresenterTest < ActiveSupport::TestCase
  test "a fresh account has everything left to do" do
    user = User.create!(email: "fresh-onboarding@example.com")
    presenter = UserOnboardingPresenter.new(user: user)

    assert presenter.visible?
    assert_equal 0, presenter.completed_count
    assert_equal 5, presenter.total_count
    assert_equal 0, presenter.progress_percent
    assert_equal %i[name city ntrp preferences availability], presenter.items.map(&:key)
  end

  test "counts what is already filled in" do
    user = User.create!(
      email: "half-onboarding@example.com",
      name: "Half Done",
      city_name: "Yekaterinburg",
      ntrp_rating: 3.0
    )
    presenter = UserOnboardingPresenter.new(user: user)

    assert presenter.visible?
    assert_equal 3, presenter.completed_count
    assert_equal 60, presenter.progress_percent
  end

  test "disappears once everything is done" do
    user = User.create!(
      email: "done-onboarding@example.com",
      name: "Done Player",
      city_name: "Yekaterinburg",
      ntrp_rating: 4.0,
      play_formats: %w[singles],
      play_styles: %w[casual],
      availability: { "mon" => %w[evening] }
    )

    assert_not UserOnboardingPresenter.new(user: user).visible?
  end

  test "stays hidden after the user closes it" do
    user = User.create!(email: "dismissed-onboarding@example.com")
    user.dismiss_onboarding!

    assert_not UserOnboardingPresenter.new(user: user.reload).visible?
  end
end
