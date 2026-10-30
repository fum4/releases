# shellcheck shell=sh
# Sourced by test/*.test.sh: a sandbox per run (its own temp dir, HOME and signing key)
# and the assertions. Nothing outside the sandbox is read or written but the repo itself.

set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/releases-test.XXXXXXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
fails=0 passes=0

ok() { passes=$((passes + 1)); echo "ok   $*"; }
fail() { fails=$((fails + 1)); echo "FAIL $*"; }
done_testing() {
	echo "$passes passed, $fails failed"
	[ "$fails" = 0 ]
}

# check name cmd…: one assertion; the command's output is shown only on failure.
check() {
	name=$1
	shift
	if out=$("$@" 2>&1); then ok "$name"; else fail "$name"; printf '%s\n' "$out" | sed 's/^/     /'; fi
}

# refuses name pattern cmd…: cmd fails and its output matches pattern (grep -E).
refuses() {
	name=$1 pattern=$2
	shift 2
	if out=$("$@" 2>&1); then
		fail "$name (succeeded)"
		printf '%s\n' "$out" | sed 's/^/     /'
	elif printf '%s\n' "$out" | grep -Eq "$pattern"; then
		ok "$name"
	else
		fail "$name (wrong error)"
		printf '%s\n' "$out" | sed 's/^/     /'
	fi
}

# host_target prints this machine's <os>-<arch>, as install.sh names it.
host_target() {
	os=$(uname -s | tr '[:upper:]' '[:lower:]')
	case $(uname -m) in
	x86_64 | amd64) arch=amd64 ;;
	aarch64 | arm64) arch=arm64 ;;
	esac
	echo "$os-$arch"
}

# make_repo: a copy of the repo whose keys/nomadware-release.pub is a fresh test key, so
# the tests sign for real without the release key. Sets TREPO and TEST_KEY (base64).
make_repo() {
	TREPO=$SANDBOX/repo
	mkdir -p "$TREPO"
	cp -R "$REPO/bin" "$REPO/lib" "$REPO/templates" "$REPO/site" "$REPO/packages" "$REPO/config.env" "$TREPO/"
	mkdir "$TREPO/keys"
	ssh-keygen -q -t ed25519 -N '' -C test -f "$SANDBOX/test-key"
	cp "$SANDBOX/test-key.pub" "$TREPO/keys/nomadware-release.pub"
	# shellcheck disable=SC2034 # read by the test that sources this
	TEST_KEY=$(base64 <"$SANDBOX/test-key" | tr -d '\n')
	# The signing key's temp dir: a tmpfs is not guaranteed in CI, so the runner's rule.
	export GITHUB_ACTIONS=true RUNNER_TEMP="$SANDBOX"
	# Legacy packages read their GitHub release from here instead of the network.
	export RENDER_INDEX_RELEASES_DIR="$REPO/test/fixtures/releases"
	unset XDG_RUNTIME_DIR
}

# set_base url: point the test repo's public base (config.env) at url.
set_base() {
	sed -i.bak "s|^RELEASES_BASE=.*|RELEASES_BASE=$1|" "$TREPO/config.env" && rm -f "$TREPO/config.env.bak"
}

# fake_dist dir binary version: one tiny executable per target that prints its name,
# version and argv, so an install can be run and checked.
fake_dist() {
	mkdir -p "$1"
	for t in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64; do
		printf '#!/bin/sh\necho "%s %s %s" "$@"\n' "$2" "$3" "$t" >"$1/$2-$t"
		chmod 755 "$1/$2-$t"
	done
}
