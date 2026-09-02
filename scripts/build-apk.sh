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
PROJECT_NAME="$(basename "$TARGET")"
PROJECT_NAME="${PROJECT_NAME%.git}"

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

# The named cache volumes are shared with Jenkins builds of this same image, which run
# as a different host UID (whatever user Jenkins runs as). Gradle's own daemon registry
# does an internal chmod() on its state directory, which the OS only permits for the
# file's owner (or root) regardless of how open the permission bits already are - so
# plain chmod isn't enough here, ownership itself has to move to whoever's building now.
docker run --rm \
  -v android-sdk-cache:/opt/android-sdk \
  -v android-gradle-cache:/home/builder/.gradle \
  "$IMAGE" chown -R "$(id -u):$(id -g)" /opt/android-sdk /home/builder/.gradle

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v android-sdk-cache:/opt/android-sdk \
  -v android-gradle-cache:/home/builder/.gradle \
  -v "$PROJECT_DIR":/workspace -w /workspace \
  "$IMAGE" ./gradlew "$TASK"

APK="$(find "$PROJECT_DIR" -path '*/outputs/apk/*' -name '*.apk' | head -1)"
if [[ -n "$APK" ]]; then
  # Match the naming androidBuildPipeline.groovy's Package stage uses, so a local
  # build-apk.sh run and a Jenkins build of the same project produce the same name.
  APK_DIR="$(dirname "$APK")"
  METADATA="$APK_DIR/output-metadata.json"
  if [[ -f "$METADATA" ]]; then
    VERSION_NAME="$(grep -oE '"versionName"[[:space:]]*:[[:space:]]*"[^"]*"' "$METADATA" | sed -E 's/.*"([^"]*)"$/\1/')"
    VARIANT_NAME="$(grep -oE '"variantName"[[:space:]]*:[[:space:]]*"[^"]*"' "$METADATA" | sed -E 's/.*"([^"]*)"$/\1/')"
    RENAMED_APK="$APK_DIR/${PROJECT_NAME}-${VERSION_NAME}-$(date +%Y%m%d)-${VARIANT_NAME}.apk"
    cp "$APK" "$RENAMED_APK"
    APK="$RENAMED_APK"
  fi
  echo "APK ready at: $APK"
  if [[ -n "$CLEANUP_DIR" ]]; then
    echo "(This was a temporary clone and will be removed - copy the APK out first if you need it kept.)"
  fi
else
  echo "Build finished but no APK was found automatically under $PROJECT_DIR - check the Gradle output above."
fi
