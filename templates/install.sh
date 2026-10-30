#!/bin/sh
# Install @BINARY@ (@PKG@) from @BASE@/@PKG@, the release signature verified first.
#
#   curl -fsSL @BASE@/@PKG@/install.sh | sh                        # the latest release
#   curl -fsSL @BASE@/@PKG@/install.sh | sh -s -- --version vX.Y.Z  # a pinned release
#   install.sh --system            # /usr/local/bin, with sudo (root always installs there)
#   install.sh --binary ./@BINARY@-linux-amd64   # a local file: no download, no signature
#   install.sh --dry-run           # print what would happen, change nothing
#   install.sh -- <args…>          # then run @BINARY@ <args…> (everything after --)
#
# Puts @BINARY@ in ~/.local/bin (HOME must be absolute), or /usr/local/bin as root or with
# --system. Releases are <base>/<tag>/@BINARY@-<os>-<arch>, SHA256SUMS and SHA256SUMS.sig,
# and <base>/latest; NOMADWARE_RELEASES_BASE replaces the base (a test serves file://).
# SHA256SUMS must carry a signature that ssh-keygen -Y verify accepts against
# ALLOWED_SIGNERS before any hash in it is read. No credential goes with a download.
#
# Rendered from fum4/releases templates/install.sh by bin/render-install: edit the template.
set -eu

PKG=@PKG@
BINARY=@BINARY@
RELEASE_BASE=@BASE@/@PKG@
ALLOWED_SIGNERS='@ALLOWED_SIGNERS@'
SIGN_IDENTITY=@SIGN_IDENTITY@
SIGN_NAMESPACE=@SIGN_NAMESPACE@

die() { echo "install.sh: $*" >&2; exit 1; }

usage() {
	die "usage: install.sh [--version vX.Y.Z | --binary PATH] [--system] [--dry-run] [-- $BINARY args…]"
}

is_tag() {
	case $1 in
	v[0-9]*.[0-9]*.[0-9]*) ;;
	*) return 1 ;;
	esac
	case ${1#v} in
	*[!0-9.]* | *..* | *. | *.*.*.*) return 1 ;;
	esac
}

sha256() {
	if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

fetch() { curl -fsSL -o "$2" "$1"; } # url out

# mktmp makes this run's temp dir; rm_tmp removes exactly that dir and nothing else.
mktmp() {
	tmp_root=${TMPDIR:-/tmp}
	tmp=$(mktemp -d "${tmp_root%/}/$PKG-install.XXXXXXXXXX") || die "cannot create a temp dir in $tmp_root"
	tmp_own=$tmp
	trap rm_tmp EXIT
}

rm_tmp() {
	[ -n "${tmp_own:-}" ] && [ "$tmp" = "$tmp_own" ] || return 0
	case $tmp in
	*..*) return 0 ;;
	"${tmp_root%/}/$PKG"-install.*) rm -rf "${tmp:?}" ;;
	esac
}

path_hint() {
	case :$PATH: in
	*:"$1":*) ;;
	*) echo "install.sh: $1 is not on PATH: add export PATH=\"$1:\$PATH\" to your shell profile" >&2 ;;
	esac
}

# old_openssh prints the OpenSSH version when it predates 8.1, the first with -Y verify.
old_openssh() {
	v=$(ssh -V 2>&1 | sed -n 's/^OpenSSH_\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p') || return 1
	[ -n "$v" ] || return 1
	major=${v%.*} minor=${v#*.}
	[ "$major" -lt 8 ] || { [ "$major" -eq 8 ] && [ "$minor" -lt 1 ]; } || return 1
	echo "$v"
}

verify_sums() {
	# One armored signature and nothing else: ssh-keygen ignores bytes after its END line.
	if [ "$(sed -n 1p "$1/SHA256SUMS.sig")" != '-----BEGIN SSH SIGNATURE-----' ] ||
		[ "$(sed -n '$p' "$1/SHA256SUMS.sig")" != '-----END SSH SIGNATURE-----' ]; then
		die "the release's signature does not verify: do not use it, report it"
	fi
	printf '%s\n' "$ALLOWED_SIGNERS" >"$1/allowed_signers" || die "cannot write $1/allowed_signers"
	if ! ssh-keygen -Y verify -f "$1/allowed_signers" -I "$SIGN_IDENTITY" -n "$SIGN_NAMESPACE" -s "$1/SHA256SUMS.sig" <"$1/SHA256SUMS" >/dev/null 2>&1; then
		if old=$(old_openssh); then
			die "this machine's OpenSSH is $old: verifying the release's signature needs OpenSSH 8.1 or later: upgrade openssh-client, then rerun"
		fi
		die "the release's signature does not verify: do not use it, report it"
	fi
}

# say prints a step on stderr; a dry run prefixes what it would do.
say() { if [ -n "$dry" ]; then echo "dry run: would $*" >&2; else echo "$*" >&2; fi; }

# The body is one function, called on the last line: a download cut short by curl | sh
# defines nothing runnable instead of running half a script.
main() {
	version='' binary='' system='' dry=''
	tmp='' tmp_own='' tmp_root=''
	while [ $# -gt 0 ]; do
		case $1 in
		--version) [ $# -ge 2 ] || usage; version=$2; shift 2 ;;
		--binary) [ $# -ge 2 ] || usage; binary=$2; shift 2 ;;
		--system) system=1; shift ;;
		--dry-run) dry=1; shift ;;
		--) shift; break ;;
		*) usage ;;
		esac
	done
	if [ -n "$version" ] && [ -n "$binary" ]; then die "pass --version or --binary, not both"; fi
	# The version becomes a URL path: nothing but a tag gets that far.
	if [ -n "$version" ] && ! is_tag "$version"; then
		die "bad --version $version: want vMAJOR.MINOR.PATCH, e.g. v0.1.0"
	fi

	sudo=''
	if [ "$(id -u)" = 0 ]; then
		dir=/usr/local/bin
	elif [ -n "$system" ]; then
		dir=/usr/local/bin
		command -v sudo >/dev/null || die "--system installs to $dir with sudo, and there is no sudo: rerun as root, or drop --system for ~/.local/bin"
		sudo=sudo
	else
		case ${HOME:-} in
		/*) ;;
		*) die "HOME is '${HOME:-}', not an absolute path: $BINARY goes in \$HOME/.local/bin; set HOME (or pass --system) and rerun" ;;
		esac
		dir=$HOME/.local/bin
	fi
	dest=$dir/$BINARY

	if [ -z "$binary" ]; then
		os=$(uname -s | tr '[:upper:]' '[:lower:]')
		case $os in
		linux | darwin) ;;
		*) die "no $BINARY release for $os: releases are built for linux and darwin" ;;
		esac
		case $(uname -m) in
		x86_64 | amd64) arch=amd64 ;;
		aarch64 | arm64) arch=arm64 ;;
		*) die "no $BINARY release for $(uname -m): releases are built for amd64 and arm64" ;;
		esac
		asset=$BINARY-$os-$arch
		command -v ssh-keygen >/dev/null ||
			die "no ssh-keygen, which verifies the release's signature: install openssh-client, then rerun"
		mktmp
		site=${NOMADWARE_RELEASES_BASE:+${NOMADWARE_RELEASES_BASE%/}/$PKG}
		site=${site:-$RELEASE_BASE}
		if [ -z "$version" ]; then
			# Read once: the asset and SHA256SUMS below come from this one tag, so a
			# release published meanwhile can't mix two versions.
			fetch "$site/latest" "$tmp/latest" || die "download $site/latest failed: check the network, or pin a release with --version vX.Y.Z"
			version=$(sed -n 1p "$tmp/latest")
			if [ "$(awk 'END { print NR }' "$tmp/latest")" != 1 ] || ! is_tag "$version"; then
				die "$site/latest is not one vMAJOR.MINOR.PATCH line: refusing it; pin a release with --version vX.Y.Z"
			fi
		fi
		base=$site/$version
		fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS" ||
			die "download $base/SHA256SUMS failed: check the network, and that release $version exists"
		fetch "$base/SHA256SUMS.sig" "$tmp/SHA256SUMS.sig" ||
			die "download $base/SHA256SUMS.sig failed: a release without it is unsigned: do not use it, report it"
		# Before any hash is read: an unsigned SHA256SUMS vouches for nothing.
		verify_sums "$tmp"
		want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$tmp/SHA256SUMS")
		[ -n "$want" ] || die "release $version has no $asset (built for: $(awk '{ sub(/^\*/, "", $2); print $2 }' "$tmp/SHA256SUMS" | paste -sd' ' -))"
		fetch "$base/$asset" "$tmp/$asset" || die "download $base/$asset failed: check the network"
		[ "$(sha256 "$tmp/$asset")" = "$want" ] || die "checksum mismatch for $asset: refusing to install it"
		echo "install.sh: verified $PKG $version ($asset)" >&2
		binary=$tmp/$asset
	fi
	[ -f "$binary" ] || die "no such binary: $binary"

	if [ -f "$dest" ] && [ "$(sha256 "$binary")" = "$(sha256 "$dest")" ]; then
		echo "install.sh: $dest is already this build" >&2
	else
		say "install $dest"
		if [ -z "$dry" ]; then
			$sudo mkdir -p "$dir" || die "cannot create $dir"
			$sudo install -m 0755 "$binary" "$dest.new" || die "cannot write $dest.new"
			$sudo mv -f "$dest.new" "$dest" || die "cannot replace $dest"
		fi
	fi
	path_hint "$dir"

	rm_tmp # exec replaces this shell, so the EXIT trap would never clean up
	[ $# -gt 0 ] || exit 0
	if [ -n "$dry" ]; then
		say "run $dest $*"
		exit 0
	fi
	exec "$dest" "$@"
}

main "$@"
