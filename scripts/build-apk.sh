#!/usr/bin/env bash
# Build any Android project's debug APK using the shared generic Docker build image -
# no local JDK or Android SDK required, only Docker. Uses the same image and cache
# volumes as the Jenkins pipelines built from this repo, so a warm cache is shared.
#
# Usage:
#   ./scripts/build-apk.sh <git-repo-url> [gradle-task]
#   ./scripts/build-apk.sh /path/to/local/checkout [gradle-task]
#
# Examples:
#   ./scripts/build-apk.sh https://github.com/someorg/some-android-app.git
#   ./scripts/build-apk.sh ~/code/some-android-app assembleRelease
set -euo pipefail

TOOLING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?Usage: $0 <git-repo-url-or-local-path> [gradle-task]}"
TASK="${2:-assembleDebug}"
IMAGE="android-generic-build:latest"

docker build -t "$IMAGE" "$TOOLING_DIR/docker/android-generic-image"

CLEANUP_DIR=""
if [[ -d "$TARGET" ]]; then
  PROJECT_DIR="$(cd "$TARGET" && pwd)"
else
  CLEANUP_DIR="$(mktemp -d)"
  git clone "$TARGET" "$CLEANUP_DIR/project"
  PROJECT_DIR="$CLEANUP_DIR/project"
fi
trap '[[ -n "$CLEANUP_DIR" ]] && rm -rf "$CLEANUP_DIR"' EXIT

docker run --rm \
  -v android-sdk-cache:/opt/android-sdk \
  -v android-gradle-cache:/home/builder/.gradle \
  -v "$PROJECT_DIR":/workspace -w /workspace \
  "$IMAGE" ./gradlew "$TASK"

APK="$(find "$PROJECT_DIR" -path '*/outputs/apk/*' -name '*.apk' | head -1)"
if [[ -n "$APK" ]]; then
  echo "APK ready at: $APK"
  if [[ -n "$CLEANUP_DIR" ]]; then
    echo "(This was a temporary clone and will be removed - copy the APK out first if you need it kept.)"
  fi
else
  echo "Build finished but no APK was found automatically under $PROJECT_DIR - check the Gradle output above."
fi
