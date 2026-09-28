#!/bin/sh
# The Apple app's tests (mobile/ios/BackplaneTests), on this Mac and on the
# pinned iOS simulator: Swift Testing over the mock hub's scenes, and the
# snapshots of every screen.
#   scripts/test-apple.sh                      both platforms
#   scripts/test-apple.sh mac | ios            one
#   SNAPSHOT_RECORD=all scripts/test-apple.sh  record every snapshot again
#                                              (look at them before keeping them)
#   BACKPLANE_TEST_SNAPSHOTS=0 scripts/test-apple.sh mac
#                                              everything but the snapshots (CI:
#                                              the references are not checked in)
# The snapshots are drawn by the iOS 26.4 simulator and macOS 26 with the
# Xcode 26.4 SDK; another runtime draws text a little differently, so record
# and compare on the same one (BACKPLANE_TEST_SIM names another simulator).
set -eu
cd "$(dirname "$0")/.."
[ -n "${BACKPLANE_SKIP_JS:-}" ] || scripts/build-mobile.sh --js
cp mobile/build/assets/bridge.js mobile/ios/Backplane/bridge.js
scripts/apple-fixtures.sh --check
cd mobile/ios
# (xcodebuild hands TEST_RUNNER_ variables to the tests without the prefix)
export TEST_RUNNER_SNAPSHOT_RECORD="${SNAPSHOT_RECORD:-missing}"
sim=${BACKPLANE_TEST_SIM:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4}
skip=""
[ "${BACKPLANE_TEST_SNAPSHOTS:-1}" != 0 ] || skip=-skip-testing:BackplaneTests/SnapshotTests
mac() {
  xcodebuild test -project Backplane.xcodeproj -scheme Backplane -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath build/dd-test CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= $skip
}
ios() {
  xcodebuild test -project Backplane.xcodeproj -scheme Backplane -destination "$sim" \
    -derivedDataPath build/dd-test-ios CODE_SIGNING_ALLOWED=NO $skip
}
# both platforms run even when the first fails; either failing fails the run
status=0
case "${1:-all}" in
  mac) mac || status=$? ;;
  ios) ios || status=$? ;;
  all) mac || status=$?; ios || status=$? ;;
  *) echo "usage: scripts/test-apple.sh [mac|ios]" >&2; exit 2 ;;
esac
exit $status
