# GitHub → GitLab profile backup (non-destructive pilot)

GitHub is the source of truth. GitLab stores **isolated namespaced copies of GitHub branches and tags**, without altering the existing GitLab profile or overwriting divergent histories.

## Current layout

| GitHub source ref | GitLab destination ref |
| --- | --- |
| `refs/heads/main` | `refs/heads/github-mirror/main` |
| `refs/heads/feature/example` | `refs/heads/github-mirror/feature/example` |
| `refs/tags/v1.0` | `refs/tags/github-mirror/v1.0` |

- GitHub repository: `mfranchescagonzalezcejas/mfranchescagonzalezcejas`.
- GitLab repository: `mfranchescagonzalezcejas/mfranchescagonzalezcejas`.
- **Protected, original GitLab `main` stays untouched.** Its snapshot is `archive/gitlab-main-before-github-mirror-20260929`, commit `7b3a905104a44749e4e3223be04171ce7926d0c4`.
- Initial GitHub → GitLab `github-mirror/main` pilot was verified on 2026-09-29 (exact matching SHA `769b34d0a9756de507f967b9d5f3eea8933e0c34`).
- The branch/tag expansion is covered by `.github/scripts/mirror-gitlab-refs.sh`, with isolated integration tests in `.github/scripts/test-mirror-gitlab-refs.sh`.

## Execution and guarantees

The GitHub Actions workflow `.github/workflows/mirror-to-gitlab.yml`:
1. Runs credential-free integration tests on PRs to `main`.
2. After a successful test job, syncs every GitHub branch and tag on pushes to **GitHub `main`**, on manual dispatch **from `main`**, and daily at **03:23 UTC**.
3. Fetches the source's refs and checks the destinations first. GitLab branches must accept fast-forward updates; existing tags must match *exactly*.
4. Pushes each ref without force and verifies the exact remote SHA (including annotated tag objects). A conflict fails the job **before any push**.
5. Never prunes or deletes GitLab refs: deleted GitHub branches/tags remain as archival GitLab copies until explicitly reviewed and removed separately.

Note: pushes **only** to non-`main` GitHub branches will normally be picked up by the daily schedule (or manual dispatch). As with any GitHub Actions schedule on an inactive public repository, check that scheduled runs remain enabled.

A **pass** means all current source branch and tag refs were verified for that run. There is no automatic recovery from a force-push or rewritten source history; the job deliberately fails closed and requires manual investigation.

## Existing authentication: already configured (2026-09-29)

A dedicated GitLab project Deploy Key with write permission is installed for **this GitLab profile project only**. Your local private key is stored outside the repository on your own workstation. GitHub Actions holds two repository secrets:
- `GITLAB_PROFILE_MIRROR_SSH_KEY` — dedicated private SSH key.
- `GITLAB_PROFILE_MIRROR_KNOWN_HOSTS` — verified GitLab SSH public host key.

Do **not** paste either secret into PRs, issue comments, this repository, or chat. The runner uses strict SSH host-key checking and does not persist the GitHub checkout token.

If keys are ever rotated, set the new GitLab Deploy Key and update **both GitHub repository secrets** before revoking the old one.

## Verification after merging this PR

1. Check that the **Validate** and **mirror** jobs both pass in GitHub Actions for the merge commit.
2. On GitLab, verify `github-mirror/main` and `github-mirror/chore/safe-gitlab-profile-mirror` appear as branches. Additional current GitHub branches should appear automatically.
3. Compare source SHA and corresponding GitLab namespaced ref SHA:
   ```bash
   gh api repos/mfranchescagonzalezcejas/mfranchescagonzalezcejas/branches/main --jq '.commit.sha'
   glab api 'projects/84041700/repository/branches/github-mirror%2Fmain' | jq -r '.commit.id'
   ```
4. Review the action logs. No `git push --force`, `--mirror`, or ref deletions should occur.

## Scope of this backup

Included: Git commit graph reachable from **all current GitHub branches and tags** (including annotated tag objects), plus the namespaced target refs and commit/blob data they reference.

**Not included:** GitHub issues, PR discussions, releases metadata and binaries, wiki, GitHub Actions secrets/settings, Git LFS objects, branches already deleted from GitHub before initial mirroring, or immutable time-stamped/offsite backup snapshots. Plan these separately.

**Expansion to other repositories:** validate each existing GitLab counterpart before changing it; never assume a same-name repository has the same history or visibility. Preserve each original GitLab default branch independently; private GitHub projects must only be copied into private GitLab projects. Use repository-scoped credentials or a carefully scoped backup service. Do not publish an inventory of private repositories into this public profile repository.
