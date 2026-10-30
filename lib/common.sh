# shellcheck shell=sh
# Sourced by bin/* (never run): the repo's config, the package list and the checks every
# command shares. Sets ROOT before it is sourced.

die() { echo "${0##*/}: $*" >&2; exit 1; }

# The four platforms a release may carry; install.sh detects the same set.
# shellcheck disable=SC2034 # read by the bin/* that source this
TARGETS='linux-amd64 linux-arm64 darwin-amd64 darwin-arm64'
SIGN_IDENTITY=nomadware-release
SIGN_NAMESPACE=nomadware-release
PUBKEY_FILE=$ROOT/keys/nomadware-release.pub

# config_get KEY prints KEY's value from config.env (literal, split on the first =).
config_get() {
	v=$(sed -n "s/^$1=//p" "$ROOT/config.env")
	[ -n "$v" ] || die "config.env has no $1= line"
	printf '%s\n' "$v"
}

# pkg_field name n prints field n (1 name, 2 binary, 3 description, 4 source, 5 kind,
# 6 story link) of a package in ./packages, trimmed; fails when the package is not listed.
pkg_field() {
	awk -F'|' -v p="$1" -v n="$2" '
		/^[[:space:]]*(#|$)/ { next }
		{ for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
		$1 == p { print $n; found = 1; exit }
		END { exit !found }' "$ROOT/packages"
}

# pkg_names prints every package published through the bucket, in index order; legacy_names
# the legacy ones (kind "legacy"), which are downloaded from their repo's GitHub release.
pkg_names() {
	awk -F'|' '/^[[:space:]]*(#|$)/ { next } { for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) } $5 != "legacy" { print $1 }' "$ROOT/packages"
}
legacy_names() {
	awk -F'|' '/^[[:space:]]*(#|$)/ { next } { for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) } $5 == "legacy" { print $1 }' "$ROOT/packages"
}

# pkg_known: a package the bucket serves (publish, render-install, the index's main list).
pkg_known() {
	pkg_listed "$1"
	[ "$(pkg_field "$1" 5)" != legacy ] || die "$1 is legacy: it is downloaded from its GitHub release, not the bucket"
}

# legacy_known: a legacy package needs a public source repo, and may carry a story link.
legacy_known() {
	pkg_listed "$1"
	[ "$(pkg_field "$1" 5)" = legacy ] || die "$1 is not a legacy package"
	[ -n "$(pkg_field "$1" 4)" ] || die "packages: legacy package $1 needs a source repo (its downloads are that repo's GitHub release)"
	story=$(pkg_field "$1" 6)
	case $story in
	'') ;;
	https://nomadware.io/blog/ | https://nomadware.io/blog/*[!a-z0-9-]*) die "packages: story of $1 must be https://nomadware.io/blog/<slug>, got '$story'" ;;
	https://nomadware.io/blog/*) ;;
	*) die "packages: story of $1 must be https://nomadware.io/blog/<slug>, got '$story'" ;;
	esac
}

pkg_listed() {
	pkg_field "$1" 1 >/dev/null || die "unknown package '$1': add it to packages (README.md § Adding a package)"
	case $(pkg_field "$1" 5) in
	'' | legacy) ;;
	*) die "packages: kind of $1 must be empty or 'legacy', got '$(pkg_field "$1" 5)'" ;;
	esac
	# Both end up in URLs, object keys, file names and the rendered install.sh.
	for v in "$1" "$(pkg_field "$1" 2)"; do
		case $v in
		'' | -* | *[!a-z0-9-]*) die "packages: '$v' (package $1) must be lowercase letters, digits and dashes" ;;
		esac
	done
	# The optional source link is rendered into an href: only a fum4 GitHub repo URL.
	src=$(pkg_field "$1" 4)
	case $src in
	'') ;;
	https://github.com/fum4/ | https://github.com/fum4/*[!A-Za-z0-9._-]*) die "packages: source of $1 must be https://github.com/fum4/<repo>, got '$src'" ;;
	https://github.com/fum4/*) ;;
	*) die "packages: source of $1 must be https://github.com/fum4/<repo>, got '$src'" ;;
	esac
	# The description goes into JSON and HTML: escaping covers quotes and markup, not
	# control characters, so none get that far.
	if pkg_field "$1" 3 | LC_ALL=C grep -q '[[:cntrl:]]'; then
		die "packages: the description of $1 has a control character"
	fi
}

# is_tag: $1 is vMAJOR.MINOR.PATCH, the only form a release is published under.
is_tag() {
	case $1 in
	v[0-9]*.[0-9]*.[0-9]*) ;;
	*) return 1 ;;
	esac
	case ${1#v} in
	*[!0-9.]* | *..* | *. | *.*.*.*) return 1 ;;
	esac
}

sums() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# allowed_signers prints the one allowed_signers line every install.sh embeds.
allowed_signers() {
	key=$(cut -d' ' -f1,2 "$PUBKEY_FILE") || die "cannot read $PUBKEY_FILE"
	printf '%s namespaces="%s" %s\n' "$SIGN_IDENTITY" "$SIGN_NAMESPACE" "$key"
}

# sig_verify dir: dir's SHA256SUMS.sig is one armored signature of its SHA256SUMS by the
# allowed key, exactly as install.sh checks it. ssh-keygen ignores bytes after the END
# line, so a .sig with anything appended must not pass here either.
sig_verify() {
	[ "$(sed -n 1p "$1/SHA256SUMS.sig")" = '-----BEGIN SSH SIGNATURE-----' ] &&
		[ "$(sed -n '$p' "$1/SHA256SUMS.sig")" = '-----END SSH SIGNATURE-----' ] || return 1
	allowed_signers >"$1/.allowed_signers" || return 1
	ssh-keygen -Y verify -f "$1/.allowed_signers" -I "$SIGN_IDENTITY" -n "$SIGN_NAMESPACE" \
		-s "$1/SHA256SUMS.sig" <"$1/SHA256SUMS" >/dev/null 2>&1
	rc=$?
	rm -f "$1/.allowed_signers"
	return $rc
}
