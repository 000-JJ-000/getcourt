# Фото или ролик, приложенный к игре. Таблица называется game_media, поэтому
# рельсовое единственное число — GameMedium.
#
# Хранилище — :local, то есть файлы лежат на диске прода рядом с приложением
# (см. data-disk-runbook.md). Отсюда жёсткие лимиты ниже: без них видео забивает
# раздел за считаные загрузки. Когда появится S3/GCS, лимиты можно ослабить.
class GameMedium < ApplicationRecord
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  VIDEO_TYPES = %w[video/mp4 video/quicktime].freeze
  CONTENT_TYPES = (IMAGE_TYPES + VIDEO_TYPES).freeze

  MAX_IMAGE_SIZE = 5.megabytes
  MAX_VIDEO_SIZE = 25.megabytes
  MAX_TITLE_LENGTH = 100
  # Общий объём файлов одной игры, скрытые тоже считаются: они лежат на диске.
  MAX_BYTES_PER_GAME = 100.megabytes

  belongs_to :game
  belongs_to :user

  has_one_attached :file

  scope :visible, -> { where(hidden_at: nil) }
  # Витрина Tennis Life открыта без логина, поэтому попадание туда — отдельное
  # решение автора, а не следствие загрузки. См. GameMediaController#update.
  scope :in_feed, -> { where(show_in_feed: true) }
  scope :newest_first, -> { order(created_at: :desc) }

  validates :title, length: { maximum: MAX_TITLE_LENGTH }, allow_blank: true
  validate :file_attached
  validate :supported_content_type
  validate :within_size_limit
  validate :within_game_quota, on: :create

  def image?
    IMAGE_TYPES.include?(content_type)
  end

  def video?
    VIDEO_TYPES.include?(content_type)
  end

  def content_type
    file.attached? ? file.blob.content_type : nil
  end

  def hidden?
    hidden_at.present?
  end

  def hide!
    update!(hidden_at: Time.current)
  end

  # Превью для ленты и карточки игры. У видео варианта нет — там показываем
  # сам плеер.
  #
  # Валидация типа проверяет content_type, а его Active Storage берёт из
  # сигнатуры файла и только при неудаче — из заявленного клиентом. То есть
  # мусор, названный image/png, до сюда доедет и развалится уже на обработке
  # варианта. Лента публичная, и одно битое вложение не должно ронять страницу,
  # поэтому здесь nil вместо исключения.
  def preview_variant
    return nil unless image?

    file.variant(resize_to_limit: [ 1200, 630 ]).processed
  rescue StandardError => e
    Rails.logger.warn("[GameMedium##{id}] preview failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def file_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def supported_content_type
    return unless file.attached?
    return if CONTENT_TYPES.include?(content_type)

    errors.add(:file, :invalid_type)
  end

  def within_size_limit
    return unless file.attached?

    limit = video? ? MAX_VIDEO_SIZE : MAX_IMAGE_SIZE
    return if file.blob.byte_size <= limit

    errors.add(:file, :too_large)
  end

  def within_game_quota
    return unless file.attached? && game

    used = ActiveStorage::Blob.joins(:attachments).where(
      active_storage_attachments: { record_type: "GameMedium", name: "file",
                                    record_id: GameMedium.where(game_id: game_id).select(:id) }
    ).sum(:byte_size)
    return if used + file.blob.byte_size <= MAX_BYTES_PER_GAME

    errors.add(:base, :game_storage_full, size: MAX_BYTES_PER_GAME / 1.megabyte)
  end
end
