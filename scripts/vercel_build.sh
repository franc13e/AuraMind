#!/usr/bin/env bash
# Vercel build step: installs Flutter (cached between builds) and builds the web app.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.2}"
FLUTTER_SDK="${FLUTTER_SDK:-$HOME/flutter}"

if [ ! -x "${FLUTTER_SDK}/bin/flutter" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_SDK}"
fi
export PATH="${FLUTTER_SDK}/bin:${PATH}"

flutter config --no-analytics --enable-web >/dev/null
flutter pub get
flutter build web --release ${API_BASE:+--dart-define=API_BASE="${API_BASE}"}
