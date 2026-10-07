class AddGuestCoachNameToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :guest_coach_name, :string
  end
end
