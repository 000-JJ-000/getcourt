module Players
  # Members-only player directory. Applies visibility/eligibility first, then
  # optional filters. Always returns an ActiveRecord::Relation for pagination.
  class DirectoryQuery
    PAGE_SIZE = 20

    attr_reader :viewer, :filters

    def initialize(viewer:, filters: {})
      @viewer = viewer
      @filters = Filters.new(filters)
    end

    def relation
      scope = base_scope
      scope = apply_city(scope)
      scope = apply_ntrp(scope)
      scope = apply_play_formats(scope)
      scope = apply_play_styles(scope)
      apply_order(scope)
    end

    # Normalized filter values actually applied (invalid input dropped).
    def applied_filters
      filters.to_h
    end

    class Filters
      attr_reader :city_id, :city_name, :ntrp_min, :ntrp_max, :play_format, :play_style

      def initialize(raw = {})
        raw = raw.to_h.with_indifferent_access
        @city_id = raw[:city_id].presence&.to_i
        @city_id = nil if @city_id&.zero?
        @city_name = raw[:city_name].to_s.strip.presence
        @ntrp_min = parse_ntrp(raw[:ntrp_min])
        @ntrp_max = parse_ntrp(raw[:ntrp_max])
        if @ntrp_min && @ntrp_max && @ntrp_min > @ntrp_max
          @ntrp_min, @ntrp_max = @ntrp_max, @ntrp_min
        end
        @play_format = raw[:play_format].to_s.presence_in(User::PLAY_FORMATS)
        @play_style = raw[:play_style].to_s.presence_in(User::PLAY_STYLES)
      end

      def any?
        city_id.present? || city_name.present? || ntrp_min.present? || ntrp_max.present? ||
          play_format.present? || play_style.present?
      end

      def to_h
        {
          city_id: city_id,
          city_name: city_name,
          ntrp_min: ntrp_min&.to_s("F"),
          ntrp_max: ntrp_max&.to_s("F"),
          play_format: play_format,
          play_style: play_style
        }.compact_blank
      end

      private

      def parse_ntrp(value)
        return nil if value.blank?

        decimal = BigDecimal(value.to_s)
        return nil unless User::NTRP_RATINGS.any? { |allowed| (decimal - allowed).abs < BigDecimal("0.001") }

        decimal
      rescue ArgumentError, TypeError
        nil
      end
    end

    private

    def base_scope
      User.not_merged
        .where(telegram_generated_email: false)
        .where.not(email: [ nil, "" ])
        .where(profile_visibility: %w[members public])
        .where.not(id: viewer.id)
    end

    def apply_city(scope)
      city = resolve_filter_city
      return scope unless city || filters.city_name.present?

      if city
        names = city_match_names(city)
        scope.where(
          "users.city_id = :city_id OR lower(btrim(users.city_name)) IN (:names)",
          city_id: city.id,
          names: names.map(&:downcase)
        )
      else
        scope.where("lower(btrim(users.city_name)) = lower(btrim(?))", filters.city_name)
      end
    end

    def resolve_filter_city
      return City.find_by(id: filters.city_id) if filters.city_id
      return nil if filters.city_name.blank?

      name = filters.city_name
      City.where("lower(name) = :q OR lower(asciiname) = :q", q: name.downcase)
        .order(population: :desc)
        .first
    end

    def city_match_names(city)
      names = [ city.canonical_name, city.name, city.asciiname ].compact_blank
      normalized = City.normalize_name(city.canonical_name)
      City::NAME_ALIASES.each do |variant, canonical|
        names << variant if canonical == normalized
      end
      names.uniq
    end

    def apply_ntrp(scope)
      scope = scope.where("users.ntrp_rating >= ?", filters.ntrp_min) if filters.ntrp_min
      scope = scope.where("users.ntrp_rating <= ?", filters.ntrp_max) if filters.ntrp_max
      scope
    end

    def apply_play_formats(scope)
      return scope unless filters.play_format

      scope.where("users.play_formats @> ?::jsonb", [ filters.play_format ].to_json)
    end

    def apply_play_styles(scope)
      return scope unless filters.play_style

      scope.where("users.play_styles @> ?::jsonb", [ filters.play_style ].to_json)
    end

    def apply_order(scope)
      scope.order(Arel.sql("#{same_city_sql} ASC, #{completeness_sql} DESC, #{name_sql} ASC, users.id ASC"))
    end

    def same_city_sql
      clauses = []

      if viewer.city_id.present?
        clauses << "users.city_id = #{viewer.city_id.to_i}"
      end

      if viewer.city_name.present?
        quoted = User.connection.quote(viewer.city_name)
        clauses << "lower(btrim(users.city_name)) = lower(btrim(#{quoted}))"
      end

      return "1" if clauses.empty?

      "CASE WHEN #{clauses.join(' OR ')} THEN 0 ELSE 1 END"
    end

    def completeness_sql
      <<~SQL.squish
        (
          CASE WHEN NULLIF(btrim(users.name), '') IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN users.city_id IS NOT NULL OR NULLIF(btrim(users.city_name), '') IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN users.ntrp_rating IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN COALESCE(users.play_formats::text, '[]') NOT IN ('[]', 'null')
                 OR COALESCE(users.play_styles::text, '[]') NOT IN ('[]', 'null') THEN 1 ELSE 0 END +
          CASE WHEN COALESCE(users.availability::text, '{}') NOT IN ('{}', 'null') THEN 1 ELSE 0 END
        )
      SQL
    end

    def name_sql
      "lower(COALESCE(NULLIF(btrim(users.name), ''), ''))"
    end
  end
end
