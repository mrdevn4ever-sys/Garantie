#!/usr/bin/env bash
# Select a stable Xcode 27 and verify the iOS SDK on the GitHub runner.
set -euo pipefail
XCODE_APP=$(ls -d /Applications/Xcode_27*.app 2>/dev/null | grep -viE 'beta|release_candidate|_rc' | sort -V | tail -n 1 || true)
if [ -z "$XCODE_APP" ] || [ ! -d "$XCODE_APP/Contents/Developer" ]; then
  echo '::error::No stable Xcode 27 app is installed' >&2
  exit 1
fi
export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
XCODE_VERSION=$(xcodebuild -version | sed -n '1s/^Xcode //p')
IOS_SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
if [[ ! "$XCODE_VERSION" =~ ^27(\.[0-9]+)*$ ]] || [[ ! "$IOS_SDK_VERSION" =~ ^27(\.[0-9]+)*$ ]]; then
  echo "::error::Expected Xcode and iOS SDK 27, got Xcode=$XCODE_VERSION, iPhoneOS=$IOS_SDK_VERSION" >&2
  exit 1
fi
printf 'Xcode %s (%s); iPhoneOS SDK %s\n' "$XCODE_VERSION" "$XCODE_APP" "$IOS_SDK_VERSION"
if [ -n "${GITHUB_ENV:-}" ]; then
  printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "$GITHUB_ENV"
fi
