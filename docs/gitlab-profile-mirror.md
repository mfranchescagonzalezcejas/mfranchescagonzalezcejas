# GitHub → GitLab profile mirror (safe pilot)

GitHub is the sole source of truth. This pilot automatically copies the GitHub `main` history to **`github-mirror/main`** inside the existing GitLab profile repository. It does **not** modify GitLab `main`, because the GitLab and GitHub profiles began with unrelated commit histories and different READMEs.

- Source: `mfranchescagonzalezcejas/mfranchescagonzalezcejas` on GitHub, `main`.
- Destination: `mfranchescagonzalezcejas/mfranchescagonzalezcejas` on GitLab, `github-mirror/main`.
- Original GitLab `main` snapshot: `archive/gitlab-main-before-github-mirror-20260929` (commit `7b3a905104a44749e4e3223be04171ce7926d0c4`).
- GitHub main at audit: `4acba7ec12513ef9940ab079074e5b74ffa43aa7`.
- Triggers: pushes to GitHub `main`, manual dispatch, and daily retry at 03:23 UTC.
- Safety: no force-push, no prune, no deletion, and an exact SHA verification after every push. If the mirror has diverged, the workflow **fails** rather than overwriting anything.

## One-time authentication (perform locally; never paste private keys into issues, PRs, or chats)

Use a **dedicated GitLab project deploy key with write permission**, rather than a GitLab account-wide token. From your own Arch Linux workstation:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
test ! -e ~/.ssh/github-to-gitlab-profile || { echo "Key exists; stop and reuse or back it up"; exit 1; }
ssh-keygen -t ed25519 -f ~/.ssh/github-to-gitlab-profile \
  -C "github-actions-profile-mirror" -N ''
cat ~/.ssh/github-to-gitlab-profile.pub
```

In the [existing GitLab profile repository](https://gitlab.com/mfranchescagonzalezcejas/mfranchescagonzalezcejas), visit **Settings → Repository → Deploy keys → Add new key**. Paste **only** the `.pub` key, name it `github-actions-profile-mirror`, and select **Grant write permissions**. The destination mirror branch is deliberately separate from protected `main`.

Still on your own machine, capture GitLab.com's SSH host public key **and confirm its fingerprint matches the fingerprint published on GitLab.com's [instance configuration page](https://gitlab.com/help/instance_configuration#ssh-host-keys-fingerprints)** before using the captured key:

```bash
ssh-keyscan -t ed25519 gitlab.com 2>/dev/null > ~/.ssh/gitlab-mirror-known_hosts
ssh-keygen -lf ~/.ssh/gitlab-mirror-known_hosts -E sha256
```

After confirming the fingerprint, configure the following two **GitHub Actions repository secrets** in **Settings → Secrets and variables → Actions**. Alternatively, with `gh` authenticated on your own workstation, enter:

```bash
gh secret set GITLAB_PROFILE_MIRROR_SSH_KEY \
  -R mfranchescagonzalezcejas/mfranchescagonzalezcejas \
  < ~/.ssh/github-to-gitlab-profile
gh secret set GITLAB_PROFILE_MIRROR_KNOWN_HOSTS \
  -R mfranchescagonzalezcejas/mfranchescagonzalezcejas \
  < ~/.ssh/gitlab-mirror-known_hosts
```

Do not share the private key with ChatGPT or add it to Git. Never turn off strict host-key checking to work around a verification failure.

## Activate and verify

1. Review and merge the draft PR once the two secrets and GitLab deploy key are configured.
2. Open GitHub **Actions → Mirror profile to GitLab (safe pilot) → Run workflow** to trigger the initial copy. Merging to GitHub main also triggers the first run.
3. In GitLab, switch to branch `github-mirror/main`. Confirm both the README and `assets/ado-adosense.gif` exist.
4. Compare `git rev-parse main` on GitHub with the SHA GitLab reports for `github-mirror/main`. They must match exactly.
5. Make a normal GitHub README change and ensure the next workflow run advances the GitLab branch.

**Pilot scope:** Only GitHub `main` is mirrored, including its existing commit history. Issues, pull requests, GitHub settings, tags and other branches are not covered by this workflow. Later we can extend backup coverage to additional refs and independent, versioned snapshots.

**Do not switch GitLab's protected `main` or force-push over it** until the preserved GitLab-specific README is consciously accounted for. The snapshot branch is not a replacement for an offline or independent backup.
