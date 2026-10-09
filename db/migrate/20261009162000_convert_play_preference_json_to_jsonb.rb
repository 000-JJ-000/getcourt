class ConvertPlayPreferenceJsonToJsonb < ActiveRecord::Migration[8.1]
  def up
    change_column :users, :play_formats, :jsonb, default: [], null: false, using: "play_formats::jsonb"
    change_column :users, :play_styles, :jsonb, default: [], null: false, using: "play_styles::jsonb"
  end

  def down
    change_column :users, :play_formats, :json, default: [], null: false, using: "play_formats::json"
    change_column :users, :play_styles, :json, default: [], null: false, using: "play_styles::json"
  end
end
