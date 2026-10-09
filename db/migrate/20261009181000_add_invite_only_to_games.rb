class AddInviteOnlyToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :invite_only, :boolean, default: false, null: false
    add_index :games, :invite_only
  end
end
