#!/bin/sh
# Legacy packages in bin/render-index: rendered from a GitHub release fixture
# (test/fixtures/releases/<repo>.json, via RENDER_INDEX_RELEASES_DIR): no network.
#
#   sh test/legacy.test.sh
# shellcheck source=test/lib.sh
. "$(dirname "$0")/lib.sh"

make_repo
st=$SANDBOX/state idx=$SANDBOX/idx rel=$SANDBOX/releases
mkdir -p "$st" "$rel"
render() { "$TREPO/bin/render-index" "$st" "$idx"; }
# only_legacy: a packages file with just the legacy row, so the bucket list is empty.
printf '%s\n' 'openkit | openkit | The <b>platform</b> & "agents". | https://github.com/fum4/openkit | | legacy | https://nomadware.io/blog/why-we-built-openkit' >"$TREPO/packages"

check 'render with a legacy package' render
html=$idx/index.html
check 'a Legacy section with its muted line' sh -c "grep -qF '<h2 class=\"section\" id=\"legacy-title\">Legacy</h2>' '$html' && grep -qF 'No longer developed. Downloads stay up.' '$html'"
check 'the entry has a legacy tag, version and date' sh -c "grep -qF '<span class=\"tag\">legacy</span> <span class=\"meta\"><span class=\"ver\">v0.0.66</span> · 2026-03-24</span>' '$html'"
check 'the legacy version is muted, never the accent (<b>)' sh -c "grep -qF '.ver { color: var(--dim); }' '$html' && ! sed -n '/id=\"legacy\"/,\$p' '$html' | grep -q '<b>'"
check 'the GitHub icon opens the repo in a new tab' grep -qF '<a class="src" href="https://github.com/fum4/openkit" target="_blank" rel="noopener noreferrer" aria-label="Source on GitHub"><svg' "$html"
check 'the three download labels, in order' sh -c "grep -o 'class=\"p\" href=\"[^\"]*\">[^<]*' '$html' | sed 's/.*>//' | paste -sd'|' - | grep -qxF 'macOS (Apple Silicon) .dmg|macOS (Intel) .dmg|Linux .AppImage'"
check 'downloads link the release assets' sh -c "grep -qF 'href=\"https://github.com/fum4/openkit/releases/download/v0.0.66/OpenKit-0.0.66-arm64.dmg\">macOS (Apple Silicon) .dmg' '$html' && grep -qF 'OpenKit-0.0.66.AppImage\">Linux .AppImage' '$html'"
check 'zips, blockmaps and latest-mac.yml are not linked' sh -c "! grep -E 'zip|blockmap|latest-mac' '$html'"
check 'no terminal for a legacy entry' sh -c "! grep -q 'data-window=' '$html' && ! grep -q 'curl -fsSL' '$html'"
check 'no SHA256SUMS link for a legacy entry' sh -c "! grep -q 'SHA256SUMS</a>' '$html'"
check 'the story link' grep -qF '<a class="story" href="https://nomadware.io/blog/why-we-built-openkit">why it stopped →</a>' "$html"
check 'the description is escaped' grep -qF 'The &lt;b&gt;platform&lt;/b&gt; &amp; &quot;agents&quot;.' "$html"
check 'the CSP is unchanged by the section' grep -qF "img-src 'self' data:; base-uri 'none'" "$html"
check 'index.json lists it under legacy' sh -c "jq -e '.packages == [] and .legacy[0].name == \"openkit\" and .legacy[0].version == \"v0.0.66\" and (.legacy[0].assets | map(.label)) == [\"macOS (Apple Silicon) .dmg\",\"macOS (Intel) .dmg\",\"Linux .AppImage\"]' '$idx/index.json'"

# Only assets the release has get a link.
jq 'del(.assets[] | select(.name | test("x64.dmg$")))' "$REPO/test/fixtures/releases/openkit.json" >"$rel/openkit.json"
check 'render without the Intel dmg' env RENDER_INDEX_RELEASES_DIR="$rel" "$TREPO/bin/render-index" "$st" "$idx"
check 'the missing asset has no link' sh -c "! grep -qF 'Intel' '$html' && [ \$(grep -o 'class=\"p\"' '$html' | wc -l) = 2 ]"
# An asset from somewhere other than the repo's own release downloads is not linked.
jq '.assets[0].name = "OpenKit-1.0.0.AppImage" | .assets[0].browser_download_url = "https://evil.example/x.AppImage"' "$REPO/test/fixtures/releases/openkit.json" >"$rel/openkit.json"
check 'render with a foreign asset url' env RENDER_INDEX_RELEASES_DIR="$rel" "$TREPO/bin/render-index" "$st" "$idx"
check 'the foreign url is not linked' sh -c "! grep -q 'evil.example' '$html'"

# Refusals: a stale or half-read page is never written.
rm -f "$rel/openkit.json"
refuses 'no release fixture / fetch failure' 'no release fixture for openkit' env RENDER_INDEX_RELEASES_DIR="$rel" "$TREPO/bin/render-index" "$st" "$idx"
printf 'not json' >"$rel/openkit.json"
refuses 'a release that is not JSON' 'not a vMAJOR|not JSON|parse' env RENDER_INDEX_RELEASES_DIR="$rel" "$TREPO/bin/render-index" "$st" "$idx"
jq '.tag_name = "latest"' "$REPO/test/fixtures/releases/openkit.json" >"$rel/openkit.json"
refuses 'a release tag that is not a tag' 'not a vMAJOR' env RENDER_INDEX_RELEASES_DIR="$rel" "$TREPO/bin/render-index" "$st" "$idx"
jq '.assets = [{name:"latest-mac.yml",browser_download_url:"https://github.com/fum4/openkit/releases/download/v0.0.66/latest-mac.yml"}]' "$REPO/test/fixtures/releases/openkit.json" >"$rel/openkit.json"
refuses 'a release with nothing to download' 'no .dmg or .AppImage' env RENDER_INDEX_RELEASES_DIR="$rel" "$TREPO/bin/render-index" "$st" "$idx"
sed -i.bak 's,https://nomadware.io/blog/why-we-built-openkit,https://example.com/x,' "$TREPO/packages"
refuses 'a story link off the blog' 'story of openkit must be' "$TREPO/bin/render-index" "$st" "$idx"
printf '%s\n' 'openkit | openkit | desc | | | legacy' >"$TREPO/packages"
refuses 'a legacy package without a source' 'needs a source repo' "$TREPO/bin/render-index" "$st" "$idx"
printf '%s\n' 'openkit | openkit | desc | https://github.com/fum4/openkit | | legacy-ish' >"$TREPO/packages"
refuses 'an unknown kind' 'kind of openkit' "$TREPO/bin/render-index" "$st" "$idx"
printf '%s\n' 'openkit | openkit | desc | https://github.com/fum4/openkit | | legacy' >"$TREPO/packages"
refuses 'a legacy package cannot be published' 'is legacy' env RELEASES_SIGNING_KEY="$TEST_KEY" "$TREPO/bin/publish" openkit v1.0.0 "$SANDBOX"
printf '%s\n' 'openkit | openkit | desc | https://github.com/fum4/openkit | setup | legacy' >"$TREPO/packages"
refuses 'a legacy package has no post_install' 'cannot have a post_install' "$TREPO/bin/render-index" "$st" "$idx"
printf '%s\n' 'openkit | openkit | desc | https://github.com/fum4/openkit | legacy' >"$TREPO/packages"
refuses 'kind in the post_install column (a pre-post_install line)' 'kind goes in column 6' "$TREPO/bin/render-index" "$st" "$idx"

done_testing
