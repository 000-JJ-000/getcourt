# Development / Compose image for GetCourt on PostgreSQL/PostGIS.
# Multi-arch capable via docker buildx (linux/amd64, linux/arm64).
FROM ruby:4.0.7-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libffi-dev \
    libpq-dev \
    libvips42 \
    libyaml-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /rails

ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["ruby", "bin/rails", "server", "-b", "0.0.0.0"]
