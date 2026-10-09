require "test_helper"

class ActiveStorageAvatarAuthorizationTest < ActionDispatch::IntegrationTest
  test "signed blob redirect for private avatar is denied to strangers" do
    owner = User.create!(email: "as-avatar-owner-#{SecureRandom.hex(4)}@example.com", name: "Owner", profile_visibility: "private")
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    owner.avatar.attach(io: StringIO.new(png), filename: "avatar.png", content_type: "image/png")
    assert owner.avatar.attached?

    signed_id = owner.avatar.blob.signed_id
    get "/rails/active_storage/blobs/redirect/#{signed_id}/avatar.png"

    assert_response :not_found
  end
end
