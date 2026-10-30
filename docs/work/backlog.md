# Backlog

Engineering follow-ups for this repo. Format and rules: devbox `docs/work/README.md`.

## Top bar and terminal sync with nomadware.io · 2026-10-30 · S

`templates/index.html` carries a static copy of nomadware.io's top bar (logo SVG, wordmark,
the `blog` / `get in touch` links, sizes and the ≤640 / ≤380 px steps), copied from
Nomadware.io `apps/marketing/src/components/site-nav.astro`, `logo-mark.astro`,
`wordmark.astro` and `tokens.css`, and of the blog's code window (`src/styles/prose.css`,
`window.css`: frame, bar, lights, colours) for the install terminal, and of that window's behaviour
(close / fold / in-page full screen, hover glyphs): `window.css`, `window-lights.ts`,
`window-controls.ts`, `window-maximize.ts` ported to plain inline JS in the template and
`bin/render-index`, minus the analytics, and of the page's grid paper and column halo
(`global.css` `.frame`, `tokens.css` `--grid*` / `--halo-column`; static, without the cursor
warp of `grid-warp.ts`, the film grain and the site's no-light-scheme: light is the same lines in
black). Nothing keeps them in
step: a nav or window change on the site
leaves this page stale. First step: a check in Nomadware.io (it has both sources on the
box, and this repo is public, its CI can't read the private one) that extracts the nav's
labels + hrefs, the logo's `<rect>`s and the window tokens (frame, bar, light colours) and
diffs them (and the window script's behaviour: the light labels, the fold and full-screen hooks) against
`~/code/releases/templates/index.html`, run in its `pre-merge` so a nav change fails until
the copy follows.
