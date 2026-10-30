# secrets/

Encrypted with the repo's age key (`~/.config/age/releases.key`; recipients in
`recipients.txt`). Engine and rules: devbox `docs/repo-secrets.md`. Rows: `manifest`.

| File | Holds | Credential (Cloudflare name) | Who reads it | Breaks on revoke |
|---|---|---|---|---|
| `publish.env.age` | `RELEASES_SIGNING_KEY` — base64 of the `nomadware-release` ed25519 private key (public half: `keys/nomadware-release.pub`) | — (a key, not a token) | `mise run publish` (box: ephedra); package repos' Actions via `secrets:gh-push` | every publish (a new key also needs a new `keys/*.pub` and a release of every installer) |
| `publish.env.age` | `R2_RELEASES_ACCESS_KEY_ID`, `R2_RELEASES_SECRET_ACCESS_KEY` | `releases-publish` — Account API token, Object Read & Write, bucket `nomadware-releases` only | same | every publish |
| `releases-terraform-state.env.age` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `releases-terraform-state` — Account API token, Object Read & Write, bucket `releases-backup` only | `mise run tf`, `mise run tf:github` (state backend) | Terraform here |
| `releases-terraform-cloudflare.env.age` | `CLOUDFLARE_API_TOKEN` | `releases-terraform-cloudflare` — Account API token, Workers R2 Storage: Edit | `mise run tf` (creates the bucket) | Terraform here |

Pending (minted by the owner, then added here as manifest rows): `releases-publish`'s two
lines in `publish.env.age` (`mise run secrets:edit secrets/publish.env.age`), and the two
`releases-terraform-*` files.

The R2 endpoint, bucket and public base are config, not secrets: `../config.env`.

## Package repos' Actions secrets

A public package publishes from its own release workflow (`uses: fum4/releases@v1`), so
`publish.env.age`'s three lines are its Actions secrets, pushed from here, never typed:

```sh
mise run secrets:gh-push -- fum4/waker     # after every edit of publish.env.age, once merged
gh secret list -R fum4/waker               # drift: the three names, nothing else from here
```

Repos holding them: `fum4/waker`.

## Rotating the signing key

Every installed `install.sh` and every binary that verifies its own downloads (ephedra's
`eph`) trusts the key it shipped with, for the tags it fetches. A new key: generate it,
replace `keys/nomadware-release.pub` and `RELEASES_SIGNING_KEY`, publish a release of
every package (each renders a new `install.sh`), `secrets:gh-push` to every repo above.
Old tags keep their old signatures; their per-tag `install.sh` still verifies them.
