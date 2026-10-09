# PostGIS Docker images install tiger/topology extensions. They must not land in
# schema.rb or db:schema:load fails on a clean database that only has postgis.
Rake::Task["db:schema:dump"].enhance do
  path = Rails.root.join("db/schema.rb")
  next unless path.exist?

  cleaned = path.read
    .gsub(/^  enable_extension "fuzzystrmatch"\n/, "")
    .gsub(/^  enable_extension "tiger\.postgis_tiger_geocoder"\n/, "")
    .gsub(/^  enable_extension "topology\.postgis_topology"\n/, "")
  path.write(cleaned)
end
