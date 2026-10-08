class EnablePostgis < ActiveRecord::Migration[8.1]
  def change
    enable_extension "postgis" unless extension_enabled?("postgis")
  end
end
