# Private User avatars must not be reachable via default Active Storage signed
# blob/representation URLs. Directory and profile pages stream through
# UsersController#avatar; this closes the direct-route bypass for avatar blobs.
Rails.application.config.to_prepare do
  authorize = Module.new do
    extend ActiveSupport::Concern

    included do
      before_action :authorize_user_avatar_blob!
    end

    private

    def authorize_user_avatar_blob!
      blob = instance_variable_get(:@blob)
      return unless blob

      attachment = ActiveStorage::Attachment.find_by(blob_id: blob.id, name: "avatar", record_type: "User")
      return unless attachment

      user = attachment.record
      return if user&.profile_visible_to?(active_storage_viewer)

      head :not_found
    end

    def active_storage_viewer
      user_id = session[:user_id]
      return if user_id.blank?

      raw = session[:authenticated_at]
      return if raw.blank?

      authenticated_at = Time.iso8601(raw.to_s)
      ttl = Rails.application.config.x.session_absolute_ttl || 30.days
      return if authenticated_at <= ttl.ago

      User.find_by(id: user_id)
    rescue ArgumentError, TypeError
      nil
    end
  end

  [
    "ActiveStorage::Blobs::RedirectController",
    "ActiveStorage::Blobs::ProxyController",
    "ActiveStorage::Representations::RedirectController",
    "ActiveStorage::Representations::ProxyController"
  ].each do |const_name|
    next unless Object.const_defined?(const_name)

    controller = const_name.constantize
    next if controller.included_modules.include?(authorize)

    controller.include(authorize)
  end
end
