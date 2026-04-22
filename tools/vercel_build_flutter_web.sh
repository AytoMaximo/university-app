#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.38.9"
FLUTTER_ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_CACHE_ROOT="${VERCEL_CACHE_DIR:-${PWD}/.vercel-cache}/flutter"
FLUTTER_HOME="${FLUTTER_CACHE_ROOT}/${FLUTTER_VERSION}"
FLUTTER_BIN="${FLUTTER_HOME}/bin/flutter"

if [ ! -x "${FLUTTER_BIN}" ]; then
  rm -rf "${FLUTTER_HOME}"
  mkdir -p "${FLUTTER_CACHE_ROOT}"
  curl --fail --location --show-error "${FLUTTER_ARCHIVE_URL}" | tar -xJ -C "${FLUTTER_CACHE_ROOT}"
  mv "${FLUTTER_CACHE_ROOT}/flutter" "${FLUTTER_HOME}"
fi

export PATH="${FLUTTER_HOME}/bin:${PATH}"

git config --global --add safe.directory "${PWD}" || true
git config --global --add safe.directory "${FLUTTER_HOME}" || true

if [ "${VERCEL:-}" = "1" ]; then
  cp "tools/pubspec_map_web.yaml" "pubspec.yaml"
  rm -f "pubspec.lock"
fi

flutter config --no-analytics
flutter config --enable-web
flutter pub get
flutter build web --release --target lib/main/main_map_web.dart
