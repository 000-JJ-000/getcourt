module Communities
  # Members-only community directory. Private communities are excluded from
  # listings and counts; discovery is public/open communities only.
  class DirectoryQuery
    PAGE_SIZE = 20

    def initialize(viewer:, filters: {})
      @viewer = viewer
      @filters = Filters.new(filters)
    end

    def relation
      scope = Community.publicly_listed
      scope = apply_name(scope)
      scope = apply_city(scope)
      scope = apply_focus(scope)
      scope.ordered
    end

    def applied_filters
      @filters.to_h
    end

    class Filters
      attr_reader :q, :city_id, :city_name, :play_focus

      def initialize(raw = {})
        raw = raw.to_h.with_indifferent_access
        @q = raw[:q].to_s.strip.presence
        @city_id = raw[:city_id].presence&.to_i
        @city_id = nil if @city_id&.zero?
        @city_name = raw[:city_name].to_s.strip.presence
        @play_focus = raw[:play_focus].to_s.presence_in(Community::PLAY_FOCUSES)
      end

      def to_h
        { q: q, city_id: city_id, city_name: city_name, play_focus: play_focus }.compact_blank
      end
    end

    private

    def apply_name(scope)
      return scope if @filters.q.blank?

      scope.where("communities.name ILIKE ?", "%#{Community.sanitize_sql_like(@filters.q)}%")
    end

    def apply_city(scope)
      city = resolve_filter_city
      if city
        names = city_match_names(city)
        scope.where(
          "communities.city_id = :city_id OR lower(btrim(communities.city_name)) IN (:names)",
          city_id: city.id,
          names: names.map(&:downcase)
        )
      elsif @filters.city_name.present?
        scope.where("lower(btrim(communities.city_name)) = lower(btrim(?))", @filters.city_name)
      else
        scope
      end
    end

    def apply_focus(scope)
      return scope if @filters.play_focus.blank?
      return scope if @filters.play_focus == "both"

      scope.where(play_focus: [ @filters.play_focus, "both" ])
    end

    def resolve_filter_city
      return City.find_by(id: @filters.city_id) if @filters.city_id
      return nil if @filters.city_name.blank?

      City.where("lower(name) = :q OR lower(asciiname) = :q", q: @filters.city_name.downcase)
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
  end
end
