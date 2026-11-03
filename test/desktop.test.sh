#!/bin/sh
# Desktop releases share the signed, immutable pipeline with CLI releases.
# shellcheck source=test/lib.sh
. "$(dirname "$0")/lib.sh"
make_repo
export FAKE_BUCKETS="$SANDBOX/buckets" FAKE_LOG="$SANDBOX/rclone.log"
mkdir -p "$FAKE_BUCKETS/nomadware-releases" "$SANDBOX/bin"
cp "$REPO/test/fake-rclone" "$SANDBOX/bin/rclone"
chmod 755 "$SANDBOX/bin/rclone"
PATH=$SANDBOX/bin:$PATH
set_base "file://$FAKE_BUCKETS/nomadware-releases"
creds() { R2_RELEASES_ACCESS_KEY_ID=test R2_RELEASES_SECRET_ACCESS_KEY=test RELEASES_SIGNING_KEY=$TEST_KEY "$@"; }
fake_dist "$SANDBOX/dist" oh-my-disk v1.0.0
refuses 'desktop release requires DMG' 'requires.*darwin-universal.dmg' creds "$TREPO/bin/publish" oh-my-disk v1.0.0 "$SANDBOX/dist"
mkdir "$SANDBOX/dmg-only"
printf 'ad-hoc-signed-dmg-fixture\n' >"$SANDBOX/dmg-only/oh-my-disk-darwin-universal.dmg"
refuses 'desktop release requires a CLI binary' 'has no oh-my-disk-<os>-<arch> binary' creds "$TREPO/bin/publish" oh-my-disk v1.0.0 "$SANDBOX/dmg-only"
cp "$SANDBOX/dmg-only/oh-my-disk-darwin-universal.dmg" "$SANDBOX/dist/"
check 'publish CLI and desktop together' creds "$TREPO/bin/publish" oh-my-disk v1.0.0 "$SANDBOX/dist"
b=$FAKE_BUCKETS/nomadware-releases
check 'DMG is immutable release object' cmp "$SANDBOX/dist/oh-my-disk-darwin-universal.dmg" "$b/oh-my-disk/v1.0.0/oh-my-disk-darwin-universal.dmg"
check 'DMG is covered by signed checksums' grep -q 'oh-my-disk-darwin-universal.dmg' "$b/oh-my-disk/v1.0.0/SHA256SUMS"
check 'catalogue exposes desktop kind and all five assets' jq -e '.packages[] | select(.name == "oh-my-disk") | (.assets | length) == 5 and ([.assets[] | select(.kind == "desktop") | .platform] == ["darwin-universal.dmg"])' "$b/index.json"
check 'page offers direct universal DMG download' grep -q 'macOS app · Apple Silicon + Intel (.dmg)' "$b/index.html"
check 'CLI installer remains present' test -f "$b/oh-my-disk/install.sh"
cp "$SANDBOX/dist/oh-my-disk-darwin-universal.dmg" "$SANDBOX/dist/arbitrary.dmg"
refuses 'unknown desktop file refused' 'not a release asset' creds "$TREPO/bin/publish" oh-my-disk v1.0.1 "$SANDBOX/dist"
rm "$SANDBOX/dist/arbitrary.dmg"
# Existing CLI packages cannot smuggle in a desktop archive.
fake_dist "$SANDBOX/cli" waker v1.0.0
cp "$SANDBOX/dist/oh-my-disk-darwin-universal.dmg" "$SANDBOX/cli/waker-darwin-universal.dmg"
refuses 'DMG requires desktop package registration' 'not a release asset' creds "$TREPO/bin/publish" waker v1.0.0 "$SANDBOX/cli"
done_testing
