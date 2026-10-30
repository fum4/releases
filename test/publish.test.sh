#!/bin/sh
# bin/publish and bin/render-index end to end against a local stand-in for the bucket
# (test/fake-rclone) whose public URL is a file:// dir: no network, no credentials.
#
#   sh test/publish.test.sh
# shellcheck source=test/lib.sh
. "$(dirname "$0")/lib.sh"

make_repo
export FAKE_BUCKETS="$SANDBOX/buckets" FAKE_LOG="$SANDBOX/rclone.log"
mkdir -p "$FAKE_BUCKETS/nomadware-releases" "$SANDBOX/bin"
cp "$REPO/test/fake-rclone" "$SANDBOX/bin/rclone"
chmod 755 "$SANDBOX/bin/rclone"
PATH=$SANDBOX/bin:$PATH
set_base "file://$FAKE_BUCKETS/nomadware-releases"
PUBLISH=$TREPO/bin/publish
creds() { R2_RELEASES_ACCESS_KEY_ID=test R2_RELEASES_SECRET_ACCESS_KEY=test RELEASES_SIGNING_KEY=$TEST_KEY "$@"; }
fake_dist "$SANDBOX/dist" waker v1.2.0

# ── refusals: nothing reaches the bucket ──────────────────────────────────────
refuses 'unknown package' 'unknown package' creds "$PUBLISH" nope v1.0.0 "$SANDBOX/dist"
refuses 'bad tag' 'bad tag' creds "$PUBLISH" waker 1.2 "$SANDBOX/dist"
refuses 'missing dist' 'no such dist' creds "$PUBLISH" waker v1.2.0 "$SANDBOX/none"
mkdir -p "$SANDBOX/stray" && cp "$SANDBOX/dist/waker-linux-amd64" "$SANDBOX/stray/" && touch "$SANDBOX/stray/notes.txt"
refuses 'stray file in dist' 'not a release asset' creds "$PUBLISH" waker v1.2.0 "$SANDBOX/stray"
mkdir -p "$SANDBOX/wrongname" && cp "$SANDBOX/dist/waker-linux-amd64" "$SANDBOX/wrongname/eph-linux-amd64"
refuses 'another binary name' 'not a release asset' creds "$PUBLISH" waker v1.2.0 "$SANDBOX/wrongname"
refuses 'no signing key' 'RELEASES_SIGNING_KEY is not set' \
	env R2_RELEASES_ACCESS_KEY_ID=t R2_RELEASES_SECRET_ACCESS_KEY=t "$PUBLISH" waker v1.2.0 "$SANDBOX/dist"
refuses 'no R2 credentials' 'R2_RELEASES_ACCESS_KEY_ID' env RELEASES_SIGNING_KEY="$TEST_KEY" "$PUBLISH" waker v1.2.0 "$SANDBOX/dist"
other=$(ssh-keygen -q -t ed25519 -N '' -f "$SANDBOX/other" && base64 <"$SANDBOX/other" | tr -d '\n')
refuses 'a key that is not keys/nomadware-release.pub' 'does not verify' \
	env R2_RELEASES_ACCESS_KEY_ID=t R2_RELEASES_SECRET_ACCESS_KEY=t RELEASES_SIGNING_KEY="$other" "$PUBLISH" waker v1.2.0 "$SANDBOX/dist"
refuses 'a key that is not base64' 'not base64' \
	env R2_RELEASES_ACCESS_KEY_ID=t R2_RELEASES_SECRET_ACCESS_KEY=t RELEASES_SIGNING_KEY='***' "$PUBLISH" waker v1.2.0 "$SANDBOX/dist"
check 'refusals wrote nothing' test ! -s "$FAKE_LOG"

# ── a dry run builds and signs, uploads nothing ───────────────────────────────
mkdir "$SANDBOX/keep"
check 'dry run' env RELEASES_SIGNING_KEY="$TEST_KEY" RELEASES_KEEP_OUT="$SANDBOX/keep" "$PUBLISH" waker v1.2.0 "$SANDBOX/dist" --dry-run
rel=$SANDBOX/keep/release
check 'SHA256SUMS lists the four binaries and RELEASE' test "$(awk '{ print $2 }' "$rel/SHA256SUMS" | paste -sd' ' -)" = \
	'waker-linux-amd64 waker-linux-arm64 waker-darwin-amd64 waker-darwin-arm64 RELEASE'
check 'SHA256SUMS matches the binaries' sh -c "cd '$rel' && sha256sum -c SHA256SUMS"
check 'the signature verifies with the test key' sh -c "printf 'nomadware-release namespaces=\"nomadware-release\" %s\n' \"\$(cut -d' ' -f1,2 '$SANDBOX/test-key.pub')\" >'$SANDBOX/as' && ssh-keygen -Y verify -f '$SANDBOX/as' -I nomadware-release -n nomadware-release -s '$rel/SHA256SUMS.sig' <'$rel/SHA256SUMS'"
check 'install.sh is bin/render-install output' sh -c "'$TREPO/bin/render-install' waker | cmp - '$rel/install.sh'"
check 'RELEASE names the package and tag' test "$(cat "$rel/RELEASE")" = 'waker v1.2.0'
check 'the dry run touched no bucket' test ! -s "$FAKE_LOG"
check 'the signing key left no file' sh -c "! ls '$SANDBOX' | grep -q releases-sign"

# ── a real run, in order: versioned objects, read-back, install.sh, latest last ─
check 'publish waker v1.2.0' creds "$PUBLISH" waker v1.2.0 "$SANDBOX/dist"
b=$FAKE_BUCKETS/nomadware-releases
check 'latest is the tag' test "$(cat "$b/waker/latest")" = v1.2.0
check 'versioned objects are up' test -f "$b/waker/v1.2.0/SHA256SUMS.sig" -a -f "$b/waker/v1.2.0/install.sh" -a -x "$b/waker/v1.2.0/waker-darwin-arm64"
check 'latest moved last of the release' sh -c "grep -nE '^(copyto|rcat) nomadware-releases/waker/' '$FAKE_LOG' | tail -1 | grep -q 'rcat nomadware-releases/waker/latest'"
check 'install.sh moved after every versioned object' sh -c "
	last_v=\$(grep -n '^copyto nomadware-releases/waker/v1.2.0/' '$FAKE_LOG' | tail -1 | cut -d: -f1)
	inst=\$(grep -n '^copyto nomadware-releases/waker/install.sh' '$FAKE_LOG' | cut -d: -f1)
	[ \"\$inst\" -gt \"\$last_v\" ]"
check 'index.html is up' grep -q 'data-copy="curl -fsSL file://.*/waker/install.sh | sh"' "$b/index.html"
check 'fonts are up' test -f "$b/_assets/fonts/geist-latin-400-normal.woff2"
check 'index.json is valid JSON' sh -c "jq -e '.packages[0].version == \"v1.2.0\" and (.packages[0].assets | length) == 4' '$b/index.json'"

refuses 'a published tag is never released over' 'already published' creds "$PUBLISH" waker v1.2.0 "$SANDBOX/dist"
refuses 'a tag older than latest' 'newer than v1.1.9' creds "$PUBLISH" waker v1.1.9 "$SANDBOX/dist"
refuses 'an unreadable latest fails closed' 'cannot read' env FAKE_CAT_FAILS=1 R2_RELEASES_ACCESS_KEY_ID=t R2_RELEASES_SECRET_ACCESS_KEY=t RELEASES_SIGNING_KEY="$TEST_KEY" "$PUBLISH" waker v1.9.0 "$SANDBOX/dist"
refuses 'an unreadable bucket stops the index' 'cannot read' env FAKE_CAT_FAILS=1 R2_RELEASES_ACCESS_KEY_ID=t R2_RELEASES_SECRET_ACCESS_KEY=t "$PUBLISH" --index-only
check 'RELEASE is uploaded' test "$(cat "$b/waker/v1.2.0/RELEASE")" = 'waker v1.2.0'

# A run cut short (versioned objects up, latest not moved) reruns to completion.
fake_dist "$SANDBOX/dist13" waker v1.3.0
check 'publish waker v1.3.0' creds "$PUBLISH" waker v1.3.0 "$SANDBOX/dist13"
echo v1.2.0 >"$b/waker/latest"
rm "$b/waker/v1.3.0/install.sh"
check 'a rerun after a cut-short run' creds "$PUBLISH" waker v1.3.0 "$SANDBOX/dist13"
check 'the rerun moved latest' test "$(cat "$b/waker/latest")" = v1.3.0
check 'the rerun kept the signature (identical bytes)' test -f "$b/waker/v1.3.0/SHA256SUMS.sig"

# A second package lands next to the first: the index lists both, in packages order.
fake_dist "$SANDBOX/eph-dist" eph v0.2.0
rm "$SANDBOX/eph-dist/eph-darwin-amd64"
check 'publish ephedra v0.2.0 (three platforms)' creds "$PUBLISH" ephedra v0.2.0 "$SANDBOX/eph-dist"
check 'the index lists both packages, in order' sh -c "jq -r '.packages[].name' '$b/index.json' | paste -sd' ' - | grep -qx 'waker ephedra'"
check 'the index offers only the platforms built' sh -c "jq -e '(.packages[1].assets | map(.platform)) == [\"linux-amd64\",\"linux-arm64\",\"darwin-arm64\"]' '$b/index.json'"
check 'the page links no platform the release lacks' sh -c "! grep -q 'ephedra/v0.2.0/eph-darwin-amd64' '$b/index.html' && [ \$(grep -o 'ephedra/v0.2.0/eph-[a-z0-9-]*\"' '$b/index.html' | sort -u | wc -l) = 3 ]"
check 'the only script on the page is its own' sh -c "[ \$(grep -c '<script' '$b/index.html') = 1 ]"
# Links to nomadware.io and GitHub are navigation, not requests: nothing the page loads (src=, url(), a stylesheet) leaves the bucket.
# csp_ok page: the CSP's script hash is the page's inline script, hashed as a browser does.
csp_ok() {
	want=$(sed -n "s/.*script-src 'sha256-\([^']*\)'.*/\1/p" "$1")
	got=$({ printf '\n'; awk '/^<script>$/ { on = 1; next } /^<\/script>$/ { on = 0 } on' "$1"; } | openssl dgst -sha256 -binary | base64)
	[ -n "$want" ] && [ "$want" = "$got" ]
}
check 'the CSP allows exactly the inline script' csp_ok "$b/index.html"
check 'the html makes no external request' sh -c "! grep -Eo '(src=\"https?:|url\(https?:|<link[^>]*href=\"https?:)' '$b/index.html' | grep -q ."

# --index-only rebuilds from the bucket alone.
rm "$b/index.html"
check '--index-only' env R2_RELEASES_ACCESS_KEY_ID=t R2_RELEASES_SECRET_ACCESS_KEY=t "$PUBLISH" --index-only
check '--index-only rewrote index.html' grep -q 'id="ephedra"' "$b/index.html"
refuses '--index-only takes no package' 'usage' "$PUBLISH" --index-only waker

# ── render-index on its own: escaping, and a bad state dir is refused ─────────
st=$SANDBOX/state
mkdir -p "$st/waker"
echo v9.9.9 >"$st/waker/latest"
echo 2026-01-02 >"$st/waker/date"
printf '%s  waker-linux-amd64\n' "$(printf '%064d' 0 | tr 0 a)" >"$st/waker/SHA256SUMS"
sed -i.bak 's#^waker .*#waker | waker | <b>bold</b> \& "quoted"#' "$TREPO/packages"
check 'render-index' "$TREPO/bin/render-index" "$st" "$SANDBOX/idx"
check 'html escapes &, <, >, quotes' grep -qF '&lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot;' "$SANDBOX/idx/index.html"
check 'json escapes quotes' sh -c "jq -e '.packages[0].description == \"<b>bold</b> & \\\"quoted\\\"\"' '$SANDBOX/idx/index.json'"
check 'only built platforms are linked' sh -c "grep -c 'class=\"p\"' '$SANDBOX/idx/index.html' | grep -qx 1"
check 'no source link when the package has none' sh -c "! grep -q 'class=\"src\"' '$SANDBOX/idx/index.html'"
# A source: a GitHub-mark link by the name. Anything but a fum4 repo URL is refused, which
# is also what keeps markup out of the href.
sed -i.bak 's#^waker .*#waker | waker | desc | https://github.com/fum4/waker#' "$TREPO/packages"
check 'render-index with a source' "$TREPO/bin/render-index" "$st" "$SANDBOX/idx"
check 'the source link renders' grep -qF '<a class="src" href="https://github.com/fum4/waker" target="_blank" rel="noopener noreferrer" aria-label="Source on GitHub"><svg' "$SANDBOX/idx/index.html"
check 'the source link is the only one' sh -c "[ \$(grep -c 'class=\"src\"' '$SANDBOX/idx/index.html') = 1 ]"
for bad in 'http://github.com/fum4/waker' 'https://github.com/other/waker' 'https://github.com/fum4/' 'https://github.com/fum4/a/b' 'https://github.com/fum4/w"x' 'https://example.com/fum4/waker'; do
	sed -i.bak "s#^waker .*#waker | waker | desc | $bad#" "$TREPO/packages"
	refuses "source $bad is refused" 'must be https://github.com/fum4/<repo>' "$TREPO/bin/render-index" "$st" "$SANDBOX/idx"
done
sed -i.bak 's#^waker .*#waker | waker | desc#' "$TREPO/packages"
echo latest >"$st/waker/latest"
refuses 'a latest that is not a tag' 'not a vMAJOR' "$TREPO/bin/render-index" "$st" "$SANDBOX/idx"

printf 'waker | waker | tab\there\n' >"$TREPO/packages"
refuses 'a control character in a description' 'control character' "$TREPO/bin/render-install" waker

done_testing
