#!/usr/bin/env bash
# No network, real credentials, or production writes. All remotes are temporary.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
t="$(mktemp -d)"
trap 'rm -rf -- "$t"' EXIT

git init -q -b main "$t/source"
git -C "$t/source" config user.email 'mirror-test@example.invalid'
git -C "$t/source" config user.name 'Mirror integration test'
printf 'GitHub original\n' > "$t/source/README.md"
git -C "$t/source" add README.md
git -C "$t/source" commit -qm initial-github
initial_sha="$(git -C "$t/source" rev-parse HEAD)"
git -C "$t/source" tag v1
git -C "$t/source" tag -a v2 -m 'annotated'
git -C "$t/source" switch -qc feat/example
printf 'feature\n' > "$t/source/feature.txt"
git -C "$t/source" add feature.txt
git -C "$t/source" commit -qm feature
git -C "$t/source" switch -q main

git init -q --bare "$t/github.git"
git --git-dir="$t/github.git" symbolic-ref HEAD refs/heads/main
git -C "$t/source" remote add origin "$t/github.git"
git -C "$t/source" push -q origin --all
git -C "$t/source" push -q origin --tags

# Different and preserved GitLab main, reproducing the real pilot.
git init -q -b main "$t/original-gitlab"
git -C "$t/original-gitlab" config user.email 'mirror-test@example.invalid'
git -C "$t/original-gitlab" config user.name 'Mirror integration test'
printf 'GitLab original\n' > "$t/original-gitlab/README.md"
git -C "$t/original-gitlab" add README.md
git -C "$t/original-gitlab" commit -qm initial-gitlab
git init -q --bare "$t/gitlab.git"
git --git-dir="$t/gitlab.git" symbolic-ref HEAD refs/heads/main
git -C "$t/original-gitlab" remote add origin "$t/gitlab.git"
git -C "$t/original-gitlab" push -q origin main
original_gitlab_sha="$(git -C "$t/original-gitlab" rev-parse HEAD)"

git clone -q "$t/github.git" "$t/runner"
run_mirror() {
  (cd "$t/runner" && MIRROR_DESTINATION="$t/gitlab.git" \
    bash "$script_dir/mirror-gitlab-refs.sh") > "$t/run.log" 2>&1
}
assert_mirror() {
  local source_ref="$1" destination_ref="$2"
  local source_sha destination_sha
  source_sha="$(git --git-dir="$t/github.git" rev-parse "$source_ref")"
  destination_sha="$(git --git-dir="$t/gitlab.git" rev-parse "$destination_ref")"
  [[ "$source_sha" == "$destination_sha" ]]
}
assert_original() {
  [[ "$(git --git-dir="$t/gitlab.git" rev-parse refs/heads/main)" == "$original_gitlab_sha" ]]
}

run_mirror
assert_mirror refs/heads/main refs/heads/github-mirror/main
assert_mirror refs/heads/feat/example refs/heads/github-mirror/feat/example
assert_mirror refs/tags/v1 refs/tags/github-mirror/v1
assert_mirror refs/tags/v2 refs/tags/github-mirror/v2
assert_original
run_mirror # idempotent

git -C "$t/source" tag -f v1 feat/example >/dev/null
git -C "$t/source" push -q -f origin refs/tags/v1
# Make main eligible to advance too; the conflicting tag must block *all* pushes.
printf 'new main\n' >> "$t/source/README.md"
git -C "$t/source" add README.md
git -C "$t/source" commit -qm next-github-main
git -C "$t/source" push -q origin main
if run_mirror; then
  echo 'FAIL: moved tag was accepted' >&2
  exit 1
fi
grep -q 'No refs pushed' "$t/run.log"
[[ "$(git --git-dir="$t/gitlab.git" rev-parse refs/heads/github-mirror/main)" == "$initial_sha" ]]
assert_original

# Restore tag without changing original tag object (lightweight).
git -C "$t/source" tag -f v1 "$initial_sha" >/dev/null
git -C "$t/source" push -q -f origin refs/tags/v1
run_mirror
assert_mirror refs/heads/main refs/heads/github-mirror/main
assert_original

# A GitLab-only branch divergence must also fail closed.
git clone -q --branch github-mirror/main "$t/gitlab.git" "$t/gitlab-change"
git -C "$t/gitlab-change" config user.email 'mirror-test@example.invalid'
git -C "$t/gitlab-change" config user.name 'Mirror integration test'
printf 'local divergence\n' >> "$t/gitlab-change/README.md"
git -C "$t/gitlab-change" add README.md
git -C "$t/gitlab-change" commit -qm gitlab-only-change
git -C "$t/gitlab-change" push -q origin HEAD:refs/heads/github-mirror/main
if run_mirror; then
  echo 'FAIL: divergent GitLab branch was accepted' >&2
  exit 1
fi
grep -q 'Diverged GitLab branch' "$t/run.log"
assert_original

echo 'MIRROR_TESTS=PASS (branches, lightweight and annotated tags, idempotence, tag conflict, divergent branch, original main intact)'
