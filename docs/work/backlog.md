# Backlog

Engineering follow-ups for this repo. Format and rules: devbox `docs/work/README.md`.

## Top bar sync with nomadware.io · 2026-10-30 · S

`templates/index.html` carries a static copy of nomadware.io's top bar (logo SVG, wordmark,
the `blog` / `get in touch` links, sizes and the ≤640 / ≤380 px steps), copied from
Nomadware.io `apps/marketing/src/components/site-nav.astro`, `logo-mark.astro`,
`wordmark.astro` and `tokens.css`. Nothing keeps them in step: a nav change on the site
leaves this page stale. First step: a check in Nomadware.io (it has both sources on the
box, and this repo is public, its CI can't read the private one) that extracts the nav's
labels + hrefs and the logo's `<rect>`s from `site-nav.astro` and diffs them against
`~/code/releases/templates/index.html`, run in its `pre-merge` so a nav change fails until
this copy follows.
