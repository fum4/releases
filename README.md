# releases

Signed, one-line installs for every Nomadware package, served from
**https://releases.nomadware.io**:

```sh
curl -fsSL https://releases.nomadware.io/<pkg>/install.sh | sh
curl -fsSL https://releases.nomadware.io/<pkg>/install.sh | sh -s -- --version vX.Y.Z
```

No toolchain, no account. `install.sh` checks the release's `SHA256SUMS` signature
(`ssh-keygen -Y verify`, key [`keys/nomadware-release.pub`](keys/nomadware-release.pub))
before it reads a single hash, then installs to `~/.local/bin` (or `/usr/local/bin` as
root, or with `--system` via sudo). `--dry-run` changes nothing; `--binary PATH` installs a
local file; everything after `--` runs the installed binary.

This repo is the one publisher every package goes through: public packages from their
own GitHub Actions (the action in [`action.yml`](action.yml)), private ones from the box
(`bin/publish`). Same signing, same layout, same installer.

## Layout

| Path | What |
|---|---|
| `bin/publish` | sign → upload `<pkg>/<tag>/` (immutable) → read back over the public URL → `<pkg>/install.sh` → `<pkg>/latest` last → regenerate the index. Its header is the spec |
| `bin/render-install` | `templates/install.sh` filled in for one package |
| `bin/render-index` | `index.html` + `index.json` from every package's latest release |
| `templates/` | the installer and the index page (Nomadware tokens, Geist, no JS, no external request) |
| `packages` | every package: name, binary, one-line description, in index order |
| `config.env` | public base URL, bucket, R2 endpoint |
| `keys/` | the signing key's public half |
| `site/` | the page's own fonts (Geist, OFL), uploaded to `_assets/` |
| `action.yml` | the composite GitHub Action wrapping `bin/publish` |
| `infra/terraform/` | the R2 bucket `nomadware-releases` (the custom domain is in Nomadware.io) |
| `infra/github/` | this repo's ruleset: CI's `check` is the required check |
| `secrets/` | the signing key and R2 tokens, age-encrypted ([`secrets/README.md`](secrets/README.md)) |
| `test/` | installer and publisher tests: a `file://` release home, a stand-in bucket |

Bucket layout:

```
<pkg>/<tag>/<binary>-<os>-<arch>   linux|darwin × amd64|arm64; written once, never rewritten
<pkg>/<tag>/SHA256SUMS(.sig)       the signed checksums
<pkg>/<tag>/install.sh             the installer as of that release (pins a key era)
<pkg>/install.sh, <pkg>/latest     the only objects ever overwritten (max-age=60); latest is one tag line
index.html, index.json, _assets/   the index, regenerated on every publish
```

## Publishing a release

**A public package** (its CI builds it): in the release workflow, after the build, put the
binaries in one directory named `<binary>-<os>-<arch>` and add

```yaml
- uses: fum4/releases@v1
  with:
    package: waker
    version: ${{ github.ref_name }}
    dist: dist/release
    signing-key: ${{ secrets.RELEASES_SIGNING_KEY }}
    r2-access-key-id: ${{ secrets.R2_RELEASES_ACCESS_KEY_ID }}
    r2-secret-access-key: ${{ secrets.R2_RELEASES_SECRET_ACCESS_KEY }}
```

The three secrets come from this repo: `mise run secrets:gh-push -- fum4/<repo>` (never
typed by hand). The job runs on the tag push only, never on `pull_request`.

**A private package** (built on the box): from its own release task,

```sh
mise -C ~/code/releases run publish -- <pkg> <tag> /abs/path/to/dist
```

reads the same secrets in memory from `secrets/publish.env.age`. Add `--dry-run` to see
every upload without touching the bucket.

A failed run is safe to rerun: uploaded objects are skipped when identical and refused
when not, and `latest` moves only after the whole release reads back verified. Two
packages publishing at once can leave the index one release behind:
`mise run publish:index` rebuilds it from the bucket.

## Adding a package

1. A line in [`packages`](packages): `name | binary | description`.
2. Its build emits `<binary>-<os>-<arch>` for the platforms it supports (any of the four).
3. Public repo: `mise run secrets:gh-push -- fum4/<repo>`, add the repo to
   `secrets/README.md` § Package repos' Actions secrets, add the step above.
   Private: call `mise run publish` from its release task.
4. Its first publish puts it on the index.

## Checks

CI (`.github/workflows/ci.yml`, job `check`, the ruleset's required check) runs
`mise run lint` (shellcheck, the rendered installer included), `mise run tf:check` and
`mise run test`. The box's `pre-push` runs lint + tf:check as fast feedback.
