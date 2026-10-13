class AddCanceledAtToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :canceled_at, :datetime
    add_index :games, :canceled_at
  end
end
