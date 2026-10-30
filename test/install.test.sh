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

# release tag [dist-maker]: publish a signed waker <tag> into $site/waker/ the way the
# bucket lays it out, via the publisher's own dry run (its staged files are the objects it
# uploads). dist-maker builds the binaries (default fake_dist).
release() {
	rm -rf "$SANDBOX/keep" "$SANDBOX/dist"
	mkdir "$SANDBOX/keep"
	"${2:-fake_dist}" "$SANDBOX/dist" waker "$1"
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
# waker has a setup step: never let a run reach the real terminal (a test run from one
# would prompt), and start from no opt-out (CI sets CI=true); the setup tests set each.
export NOMADWARE_RELEASES_TEST_TTY="$SANDBOX/no-tty"
unset CI NONINTERACTIVE
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
# tamper: a fresh, validly signed v6.6.6 to break one piece of.
tamper() { rm -rf "$site/waker/v6.6.6" && release v6.6.6; }
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
grep -v "waker-$target" "$site/waker/v6.6.6/SHA256SUMS" >"$SANDBOX/fewer" || true
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

# ── RELEASE: the signed sums name their package and tag ───────────────────────
resign() { rm -f "$1/SHA256SUMS.sig" && ssh-keygen -q -Y sign -f "$SANDBOX/test-key" -n nomadware-release "$1/SHA256SUMS"; }
rm -rf "$site/waker/v7.7.7" && cp -R "$site/waker/v1.0.0" "$site/waker/v7.7.7"
refuses 'an older release served under a newer tag' "signed as 'waker v1.0.0', not waker v7.7.7" inst --version v7.7.7
tamper
echo 'ephedra v6.6.6' >"$site/waker/v6.6.6/RELEASE"
(cd "$site/waker/v6.6.6" && sed -i.bak "s|^[0-9a-f]*  RELEASE\$|$(sha256sum RELEASE | cut -d' ' -f1)  RELEASE|" SHA256SUMS && rm SHA256SUMS.bak)
resign "$site/waker/v6.6.6"
refuses "another package's signed release" "signed as 'ephedra v6.6.6'" inst --version v6.6.6
tamper
echo 'waker v9.9.9' >"$site/waker/v6.6.6/RELEASE"
refuses 'a RELEASE edited after signing' 'RELEASE does not match' inst --version v6.6.6
tamper
grep -v ' RELEASE$' "$site/waker/v6.6.6/SHA256SUMS" >"$SANDBOX/norel" && cp "$SANDBOX/norel" "$site/waker/v6.6.6/SHA256SUMS"
resign "$site/waker/v6.6.6"
refuses 'signed sums without RELEASE' 'no signed RELEASE' inst --version v6.6.6
check 'none of those installed anything' test ! -e "$dest"

# ── downgrade guard: latest is unsigned, so it may not go backwards ───────────
record=$HOME/.local/share/nomadware-releases/waker.version
check 'install the latest (v1.1.0)' inst
check 'the installed release is recorded' test "$(cat "$record")" = v1.1.0
echo v1.0.0 >"$site/waker/latest"
refuses 'a latest older than the installed release' 'older than the installed v1.1.0' inst
check 'the refused downgrade left v1.1.0' sh -c "'$dest' | grep -q '^waker v1.1.0 '"
check '--version downgrades on purpose' inst --version v1.0.0
check 'the record follows' test "$(cat "$record")" = v1.0.0
echo v1.1.0 >"$site/waker/latest"
check 'a newer latest upgrades' inst
check '--binary forgets the record (version unknown)' inst --binary "$SANDBOX/local-waker"
check 'no record after --binary' test ! -e "$record"
echo v1.0.0 >"$site/waker/latest"
check 'no record, no guard' inst
echo v1.1.0 >"$site/waker/latest"

# ── post-install step: packages gives waker "setup" ───────────────────────────
# setup_dist: like fake_dist, but `<binary> setup` records its args and the first line of
# its stdin in $SETUP_LOG, then exits $SETUP_EXIT: what ran, and which input it read.
setup_dist() {
	mkdir -p "$1"
	for t in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64; do
		# shellcheck disable=SC2016 # the fake binary's own $ expansions
		printf '#!/bin/sh\nif [ "$1" = setup ]; then read -r line || true; echo "$* | $line" >"$SETUP_LOG"; exit "${SETUP_EXIT:-0}"; fi\necho "%s %s %s" "$@"\n' "$2" "$3" "$t" >"$1/$2-$t"
		chmod 755 "$1/$2-$t"
	done
}
release v2.0.0 setup_dist
reset
ttyf=$SANDBOX/tty slog=$SANDBOX/setup.log ilog=$SANDBOX/install.log
echo piped >"$SANDBOX/stdin" # install.sh's own stdin: curl | sh has the script there
next="Next: run '$dest setup' to configure waker."

# setup_run answer [args…]: install v2.0.0 with "the terminal" a file holding answer and a
# newline (none: no terminal at all; eof: a terminal that sends nothing) and stdin another
# file; the run's output lands in $ilog, the step's record in $slog.
setup_run() {
	case $1 in
	none) t=$SANDBOX/no-tty ;;
	eof) t=$ttyf && : >"$t" ;;
	*) t=$ttyf && printf '%s\n' "$1" >"$t" ;;
	esac
	shift
	rm -f "$slog"
	NOMADWARE_RELEASES_TEST_TTY=$t SETUP_LOG=$slog sh "$site/waker/install.sh" --version v2.0.0 "$@" <"$SANDBOX/stdin" >"$ilog" 2>&1
}
# with_env VAR=value answer [args…]: setup_run with VAR exported.
# shellcheck disable=SC2163 # $1 is the VAR=value to export
with_env() { (export "$1" && shift && setup_run "$@"); }
printed_next() { grep -qxF "$next" "$ilog" && test ! -e "$slog" && ! grep -qF 'Set up waker now?' "$ttyf"; }
ran_setup() { grep -qx "setup | $1" "$slog"; }
skipped() { test ! -e "$slog" && grep -qxF "Skipped. $next" "$ilog"; }

check 'no terminal: installs' setup_run none
check 'no terminal: prints the next step, runs nothing' printed_next
check 'prompt, yes: installs' setup_run y
check 'prompt, yes: asked on the terminal' grep -qF 'Set up waker now? [Y/n] ' "$ttyf"
check 'prompt, yes: ran setup, stdin from the terminal' ran_setup y
check 'prompt, yes: no next-step line' sh -c "! grep -q '^Next:' '$ilog'"
check 'prompt, Enter: runs' setup_run ''
check 'prompt, Enter: ran setup' ran_setup ''
check 'prompt, YES: runs' setup_run YES
check 'prompt, YES: ran setup' ran_setup YES
check 'prompt, no: installs' setup_run n
check 'prompt, no: skipped, with the next step' skipped
check 'prompt, end of input: installs' setup_run eof
check 'prompt, end of input: skipped, with the next step' skipped
check 'CI=1: installs' with_env CI=1 y
check 'CI=1: no prompt, the next step' printed_next
check 'NONINTERACTIVE=1: installs' with_env NONINTERACTIVE=1 y
check 'NONINTERACTIVE=1: no prompt, the next step' printed_next
check '--no-setup: installs' setup_run y --no-setup
check '--no-setup: no prompt, the next step' printed_next
check 'CI empty is not an opt-out' with_env CI= y
check 'CI empty: ran setup' ran_setup y
check 'args after --: run the binary' setup_run y -- status
check 'args after --: no prompt, no next step, only the args run' sh -c "test ! -e '$slog' && ! grep -qF 'Set up' '$ttyf' && ! grep -q '^Next:' '$ilog' && grep -qx 'waker v2.0.0 $target status' '$ilog'"
check '--dry-run: changes nothing' setup_run y --dry-run
check '--dry-run: says it would offer setup, asks nothing' sh -c "grep -qxF \"dry run: would offer to run $dest setup\" '$ilog' && test ! -e '$slog' && ! grep -qF 'Set up' '$ttyf'"
check 'a failing step still exits 0' with_env SETUP_EXIT=3 y
check 'a failing step: it ran' ran_setup y
check 'a failing step: reported, with how to rerun' grep -qF "'$dest setup' failed (exit 3); $dest is installed all the same: rerun '$dest setup'" "$ilog"
check 'a failing step: the install stands' sh -c "'$dest' | grep -q '^waker v2.0.0 '"

# A package without post_install: its installer has none of it.
cp "$TREPO/packages" "$SANDBOX/packages.orig"
sed -i.bak 's#^\(waker .*\) | setup$#\1#' "$TREPO/packages" && rm -f "$TREPO/packages.bak"
check 'render an installer without post_install' sh -c "'$TREPO/bin/render-install' waker >'$SANDBOX/plain-install.sh'"
check 'it renders POST_INSTALL empty' grep -qx "POST_INSTALL=''" "$SANDBOX/plain-install.sh"
check 'no post_install: installs' sh -c "printf 'y\n' >'$ttyf' && rm -f '$slog' && NOMADWARE_RELEASES_TEST_TTY='$ttyf' SETUP_LOG='$slog' sh '$SANDBOX/plain-install.sh' --version v2.0.0 <'$SANDBOX/stdin' >'$ilog' 2>&1"
check 'no post_install: nothing extra (no prompt, no next step)' sh -c "test ! -e '$slog' && ! grep -qF 'Set up' '$ttyf' && ! grep -qE '^(Next|Skipped)' '$ilog'"

# render-install: post_install is arguments, never shell.
for bad in 'setup; reboot' "\$(id)" 'Setup' 'setup --dir=/tmp' "setup 'x'" 'setup&' 'a*'; do
	printf 'waker | waker | desc | | %s\n' "$bad" >"$TREPO/packages"
	refuses "render-install refuses post_install '$bad'" 'post_install of waker must be' "$TREPO/bin/render-install" waker
done
printf 'waker | waker | desc | | setup --yes\n' >"$TREPO/packages"
check 'render-install takes words and dashes' sh -c "'$TREPO/bin/render-install' waker | grep -qx \"POST_INSTALL='setup --yes'\""
cp "$SANDBOX/packages.orig" "$TREPO/packages"
check 'the shipped packages render waker with setup' sh -c "'$TREPO/bin/render-install' waker | grep -qx \"POST_INSTALL='setup'\""

done_testing
