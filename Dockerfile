# Multi-arch GetCourt image (linux/amd64, linux/arm64).
# Build: see docs/deployment.md (docker buildx).
ARG RUBY_VERSION=4.0.7
FROM ruby:${RUBY_VERSION}-slim AS base

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libffi8 \
    libpq5 \
    libvips42 \
    libyaml-0-2 \
    procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /rails

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1

# --- build stage: compile native gems + assets ---
FROM base AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libffi-dev \
    libpq-dev \
    libvips42 \
    libyaml-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without "development test" \
    && bundle install \
    && rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

# Asset compile does not need a live database; SECRET_KEY_BASE_DUMMY avoids baking secrets.
ENV RAILS_ENV=production \
    SECRET_KEY_BASE_DUMMY=1 \
    DATABASE_HOST=localhost \
    DATABASE_USERNAME=getcourt \
    DATABASE_PASSWORD=build \
    DATABASE_NAME=getcourt_build \
    DATABASE_CACHE_NAME=getcourt_build_cache \
    DATABASE_QUEUE_NAME=getcourt_build_queue \
    DATABASE_CABLE_NAME=getcourt_build_cable

RUN bundle exec rails assets:precompile \
    && bundle exec rails tailwindcss:build

# --- runtime ---
FROM base AS runtime

COPY --from=build ${BUNDLE_PATH} ${BUNDLE_PATH}
COPY --from=build /rails /rails

RUN chmod +x bin/docker-entrypoint bin/rails bin/jobs bin/rake \
    && mkdir -p tmp/pids tmp/cache tmp/sockets storage log \
    && useradd --create-home --shell /bin/bash rails \
    && chown -R rails:rails /rails

USER rails

ENV RAILS_ENV=production \
    SOLID_QUEUE_IN_PUMA=

EXPOSE 3000

# Health checks are defined per-service in Compose (web uses /up; worker uses process check).
# Do not add a Dockerfile HEALTHCHECK here — the same image runs web and worker roles.

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["web"]

# --- development override target (bind-mount friendly) ---
FROM base AS development

# Chromium + driver for Selenium system tests only (not in production runtime image).
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    chromium \
    chromium-driver \
    fonts-liberation \
    git \
    libffi-dev \
    libpq-dev \
    libvips42 \
    libyaml-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && chromium --version \
    && chromedriver --version

ENV RAILS_ENV=development

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN chmod +x bin/docker-entrypoint bin/rails bin/jobs bin/rake bin/dev bin/setup || true

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["web"]
