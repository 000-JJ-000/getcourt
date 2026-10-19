require "test_helper"

class PublicAppHostTest < ActiveSupport::TestCase
  include SocialEnvHelper

  test "parses scheme host and optional port from APP_HOST" do
    with_env("APP_HOST" => "https://getcourt.zanity.net") do
      assert_equal({ host: "getcourt.zanity.net", protocol: "https" }, PublicAppHost.url_options)
    end

    with_env("APP_HOST" => "http://localhost:3000") do
      assert_equal({ host: "localhost", protocol: "http", port: 3000 }, PublicAppHost.url_options)
    end

    with_env("APP_HOST" => "getcourt.zanity.net") do
      assert_equal({ host: "getcourt.zanity.net", protocol: "https" }, PublicAppHost.url_options)
    end
  end
end
