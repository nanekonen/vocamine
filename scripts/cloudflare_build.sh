#!/usr/bin/env bash

set -euo pipefail

: "${FLUTTER_VERSION:?FLUTTER_VERSION is required}"
: "${VOCAMINE_API_BASE_URL:?VOCAMINE_API_BASE_URL is required}"
: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_PUBLISHABLE_KEY:?SUPABASE_PUBLISHABLE_KEY is required}"

FLUTTER_HOME="${HOME}/flutter"

git clone \
  --depth 1 \
  --branch "${FLUTTER_VERSION}" \
  https://github.com/flutter/flutter.git \
  "${FLUTTER_HOME}"

export PATH="${FLUTTER_HOME}/bin:${PATH}"

flutter config --enable-web
flutter precache --web
flutter pub get

flutter build web --release \
  --dart-define="VOCAMINE_API_BASE_URL=${VOCAMINE_API_BASE_URL}" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}"

# Flutter does not copy additional root-level HTML files into build/web.
# Keep this file deployed so Google Search Console ownership stays verified.
cp web/google19385cc78372cafc.html build/web/google19385cc78372cafc.html
