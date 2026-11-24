#!/usr/bin/env bash
# Builds release assets for the current version into dist/.
#
#   tool/build_release.sh              # quality gates + signed APKs + checksums
#   tool/build_release.sh --with-linux # also package the Linux bundle locally
#   tool/build_release.sh --skip-tests # skip codegen/analyze/tests (repackaging)
#
# The Linux release tarball is normally produced by the tag workflow on Ubuntu
# (see .github/workflows/release.yml) for a broader glibc baseline.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

with_linux=0
skip_tests=0
for arg in "$@"; do
  case "$arg" in
    --with-linux) with_linux=1 ;;
    --skip-tests) skip_tests=1 ;;
    -h|--help)
      sed -n '2,8p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

version_line="$(grep -m1 '^version:' pubspec.yaml)"
full_version="${version_line#*:}"
full_version="${full_version//[[:space:]]/}"
version="${full_version%%+*}"
build_number="${full_version##*+}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean; commit or stash before building." >&2
  exit 1
fi

echo "==> NowPill $full_version"

if [[ $skip_tests -eq 0 ]]; then
  echo "==> Codegen + quality gates"
  dart run build_runner build
  dart format --output=none --set-exit-if-changed lib test integration_test test_driver
  flutter analyze
  flutter test
fi

dist="$ROOT/dist"
rm -rf "$dist"
mkdir -p "$dist"

echo "==> Building signed APKs"
flutter build apk --release
flutter build apk --release --split-per-abi

apk_dir="$ROOT/build/app/outputs/flutter-apk"
assets=(
  "nowpill-$version-universal.apk"
  "nowpill-$version-arm64-v8a.apk"
  "nowpill-$version-armeabi-v7a.apk"
)
cp "$apk_dir/app-release.apk" "$dist/${assets[0]}"
cp "$apk_dir/app-arm64-v8a-release.apk" "$dist/${assets[1]}"
cp "$apk_dir/app-armeabi-v7a-release.apk" "$dist/${assets[2]}"

echo "==> Verifying signatures and versions"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
build_tools="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)"
if [[ -z "$build_tools" ]]; then
  echo "No Android build-tools found under $sdk; cannot verify APKs." >&2
  exit 1
fi
apksigner="$build_tools/apksigner"
aapt2="$build_tools/aapt2"
for asset in "${assets[@]}"; do
  apk="$dist/$asset"
  certs="$("$apksigner" verify --print-certs "$apk" 2>/dev/null)"
  if ! grep -q 'CN=NowPill' <<<"$certs"; then
    echo "$asset is not signed with the NowPill upload key:" >&2
    echo "$certs" >&2
    exit 1
  fi
  badging="$("$aapt2" dump badging "$apk" 2>/dev/null | sed -n '1p')"
  echo "  $asset: $badging"
  # Flutter adds a per-ABI offset to the versionCode of split APKs
  # (1000 armeabi-v7a, 2000 arm64-v8a, 4000 x86_64).
  grep -Eq "versionCode='(1|2|4)?$build_number'" <<<"$badging"
  grep -q "versionName='$version'" <<<"$badging"
  "$apksigner" verify "$apk" >/dev/null 2>&1
done

if [[ $with_linux -eq 1 ]]; then
  echo "==> Building Linux bundle"
  flutter build linux --release
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  mkdir -p "$stage/nowpill-$version-linux-x64"
  cp -a "$ROOT/build/linux/x64/release/bundle/." "$stage/nowpill-$version-linux-x64/"
  tar -czf "$dist/nowpill-$version-linux-x64.tar.gz" \
    -C "$stage" "nowpill-$version-linux-x64"
  assets+=("nowpill-$version-linux-x64.tar.gz")
  rm -rf "$stage"
  trap - EXIT
fi

echo "==> Writing checksums"
(
  cd "$dist"
  sha256sum "${assets[@]}" >SHA256SUMS
  sha256sum "${assets[@]:0:3}" >SHA256SUMS-android
  if [[ $with_linux -eq 1 ]]; then
    sha256sum "nowpill-$version-linux-x64.tar.gz" >SHA256SUMS-linux
  fi
)

echo
echo "Release assets in $dist:"
ls -lh "$dist"
cat "$dist/SHA256SUMS"
