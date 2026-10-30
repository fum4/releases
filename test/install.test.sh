#!/bin/sh
# templates/install.sh (as bin/render-install renders it) against a file:// release home
# signed with a test key: what installs, what is refused, and that a refusal installs
# nothing. HOME is the sandbox's; nothing outside it is touched.
#
#   sh test/install.test.sh
# shellcheck source=test/lib.sh
. "$(dirname "$0")/lib.sh"

make_repo
target=$(host_target)
site=$SANDBOX/site

# release tag: publish a signed waker <tag> into $site/waker/ the way the bucket lays it
# out, via the publisher's own dry run (its staged files are the objects it uploads).
release() {
	rm -rf "$SANDBOX/keep" "$SANDBOX/dist"
	mkdir "$SANDBOX/keep"
	fake_dist "$SANDBOX/dist" waker "$1"
	RELEASES_SIGNING_KEY=$TEST_KEY RELEASES_KEEP_OUT=$SANDBOX/keep \
		"$TREPO/bin/publish" waker "$1" "$SANDBOX/dist" --dry-run >/dev/null 2>&1
	mkdir -p "$site/waker/$1"
	cp "$SANDBOX/keep/release/"* "$site/waker/$1/"
	cp "$SANDBOX/keep/release/install.sh" "$site/waker/install.sh"
}
release v1.0.0
release v1.1.0
echo v1.1.0 >"$site/waker/latest"

export HOME="$SANDBOX/home" NOMADWARE_RELEASES_BASE="file://$site"
mkdir -p "$HOME"
inst() { sh "$site/waker/install.sh" "$@"; }
dest=$HOME/.local/bin/waker
reset() { rm -rf "$HOME/.local"; }

check 'installs the latest' inst
check 'the installed binary is latest, for this machine' sh -c "'$dest' | grep -qx 'waker v1.1.0 $target'"
check 'a rerun is a no-op' sh -c "sh '$site/waker/install.sh' 2>&1 | grep -q 'already this build'"
reset
check '--version pins a release' inst --version v1.0.0
check 'the pinned release is installed' sh -c "'$dest' | grep -q '^waker v1.0.0 '"
reset
check '--dry-run' inst --dry-run
check '--dry-run installs nothing' test ! -e "$dest"
check '-- args run the installed binary' sh -c "sh '$site/waker/install.sh' -- status --json | grep -qx 'waker v1.1.0 $target status --json'"
reset
cp "$SANDBOX/dist/waker-$target" "$SANDBOX/local-waker"
check '--binary installs a local file' inst --binary "$SANDBOX/local-waker"
check '--binary needs no release home' test -x "$dest"
reset

refuses 'bad --version' 'bad --version' inst --version 1.0
refuses 'a version that does not exist' 'SHA256SUMS failed' inst --version v9.9.9
refuses '--version with --binary' 'not both' inst --version v1.0.0 --binary "$SANDBOX/local-waker"
refuses 'an unknown flag' 'usage' inst --frobnicate

# Tampering: each refused, and nothing installed.
tamper() { rm -rf "$site/waker/v6.6.6" && cp -R "$site/waker/v1.1.0" "$site/waker/v6.6.6"; }
tamper
printf '%064d  waker-%s\n' 0 "$target" >"$site/waker/v6.6.6/SHA256SUMS"
refuses 'a SHA256SUMS edited after signing' 'does not verify' inst --version v6.6.6
tamper
echo junk >>"$site/waker/v6.6.6/SHA256SUMS.sig"
refuses 'bytes appended to the signature' 'does not verify' inst --version v6.6.6
tamper
rm "$site/waker/v6.6.6/SHA256SUMS.sig"
refuses 'an unsigned release' 'unsigned' inst --version v6.6.6
tamper
ssh-keygen -q -t ed25519 -N '' -f "$SANDBOX/evil"
rm "$site/waker/v6.6.6/SHA256SUMS.sig"
ssh-keygen -q -Y sign -f "$SANDBOX/evil" -n nomadware-release "$site/waker/v6.6.6/SHA256SUMS"
refuses 'a signature by another key' 'does not verify' inst --version v6.6.6
tamper
cp "$site/waker/v1.0.0/waker-$target" "$site/waker/v6.6.6/waker-$target"
refuses 'a binary swapped after signing' 'checksum mismatch' inst --version v6.6.6
tamper
grep -v "waker-$target" "$site/waker/v1.1.0/SHA256SUMS" >"$SANDBOX/fewer" || true
check 'a release missing this platform (setup)' sh -c "
	cp '$SANDBOX/fewer' '$site/waker/v6.6.6/SHA256SUMS' && rm '$site/waker/v6.6.6/SHA256SUMS.sig' &&
	ssh-keygen -q -Y sign -f '$SANDBOX/test-key' -n nomadware-release '$site/waker/v6.6.6/SHA256SUMS'"
refuses 'a release missing this platform' "has no waker-$target" inst --version v6.6.6
check 'no refusal installed anything' test ! -e "$dest"

printf 'v1.1.0\nv1.0.0\n' >"$site/waker/latest"
refuses 'a latest of two lines' 'not one vMAJOR' inst
echo 'v1.1.0/../../x' >"$site/waker/latest"
refuses 'a latest that is not a tag' 'not one vMAJOR' inst
echo v1.1.0 >"$site/waker/latest"

refuses 'a relative HOME' 'not an absolute path' env HOME=relative sh "$site/waker/install.sh"

done_testing
