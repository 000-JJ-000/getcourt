class AddPlayerProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.decimal :ntrp_rating, precision: 2, scale: 1
      t.json :play_formats, default: [], null: false
      t.json :play_styles, default: [], null: false
      t.json :availability, default: {}, null: false
      t.string :profile_visibility, default: "members", null: false
      t.boolean :show_stats_on_profile, default: true, null: false
      t.boolean :show_telegram_on_profile, default: false, null: false
      t.references :city, foreign_key: true, null: true
    end

    add_index :users, :profile_visibility
    add_index :users, :ntrp_rating
  end
end
