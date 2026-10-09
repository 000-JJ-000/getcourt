class UserOnboardingPresenter
  Item = Data.define(:key, :completed, :path)

  attr_reader :user

  def initialize(user:, routes: Rails.application.routes.url_helpers)
    @user = user
    @routes = routes
  end

  # Hidden once everything is done, or once the newcomer says they are done with it.
  def visible?
    user.present? && !user.onboarding_dismissed? && items.any? { |item| !item.completed }
  end

  def items
    @items ||= [
      Item.new(key: :name, completed: user.name.present?, path: @routes.profile_account_path),
      Item.new(key: :city, completed: user.city_name.present?, path: @routes.profile_account_path),
      Item.new(key: :ntrp, completed: user.ntrp_rating.present?, path: @routes.profile_account_path),
      Item.new(key: :preferences, completed: user.play_preferences_present?, path: @routes.profile_account_path),
      Item.new(key: :availability, completed: user.availability_present?, path: @routes.profile_account_path)
    ].freeze
  end

  def completed_count
    items.count(&:completed)
  end

  def total_count
    items.size
  end

  def progress_percent
    return 100 if total_count.zero?

    (completed_count * 100.0 / total_count).round
  end
end
