#!/usr/bin/env bash
# Copy all GitHub source branches/tags into an isolated GitLab namespace.
# NEVER force-push or delete remote refs. GitHub is authoritative.
set -euo pipefail

destination="${MIRROR_DESTINATION:-git@gitlab.com:mfranchescagonzalezcejas/mfranchescagonzalezcejas.git}"
branch_prefix='refs/heads/github-mirror/'
tag_prefix='refs/tags/github-mirror/'

git fetch --no-write-fetch-head origin \
  '+refs/heads/*:refs/remotes/origin/*' \
  '+refs/tags/*:refs/tags/*'

declare -A remote_sha=()
remote_refs="$(git ls-remote --refs "$destination" \
  'refs/heads/github-mirror/*' 'refs/tags/github-mirror/*')"
while IFS=$'\t' read -r sha ref; do
  [[ -n "$ref" ]] || continue
  remote_sha["$ref"]="$sha"
done <<< "$remote_refs"

declare -a sources=() targets=() expected_shas=()

# Include every GitHub branch, including ones with '/' in their names.
while IFS= read -r source; do
  [[ "$source" == 'refs/remotes/origin/HEAD' ]] && continue
  branch="${source#refs/remotes/origin/}"
  target="${branch_prefix}${branch}"
  expected="$(git rev-parse --verify "${source}^{commit}")"
  if [[ -n "${remote_sha[$target]+present}" && "${remote_sha[$target]}" != "$expected" ]]; then
    # Refuse a non-fast-forward destination update rather than overwriting history.
    if ! git merge-base --is-ancestor "${remote_sha[$target]}" "$expected"; then
      echo "::error::Diverged GitLab branch: $target. No refs pushed." >&2
      exit 1
    fi
  fi
  sources+=("$source")
  targets+=("$target")
  expected_shas+=("$expected")
done < <(git for-each-ref --format='%(refname)' refs/remotes/origin)

# Include lightweight and annotated tags; both are checked by exact object SHA.
while IFS= read -r source; do
  tag="${source#refs/tags/}"
  target="${tag_prefix}${tag}"
  expected="$(git rev-parse --verify "$source")"
  if [[ -n "${remote_sha[$target]+present}" && "${remote_sha[$target]}" != "$expected" ]]; then
    echo "::error::GitLab tag differs: $target. No refs pushed." >&2
    exit 1
  fi
  sources+=("$source")
  targets+=("$target")
  expected_shas+=("$expected")
done < <(git for-each-ref --format='%(refname)' refs/tags)

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "::error::No GitHub branches or tags found; refusing empty mirror." >&2
  exit 1
fi

echo "Preflight PASS: ${#sources[@]} source refs; no divergence detected."

# Push only after ALL refs have passed preflight. If GitLab changes during the
# run, a push can still fail safely without force; next run resumes partial work.
for index in "${!sources[@]}"; do
  git push "$destination" "${sources[$index]}:${targets[$index]}"
done

# Verify the destination's precise ref/object SHA, not only a successful exit.
verified_refs="$(git ls-remote --refs "$destination" \
  'refs/heads/github-mirror/*' 'refs/tags/github-mirror/*')"
declare -A verified=()
while IFS=$'\t' read -r sha ref; do
  [[ -n "$ref" ]] || continue
  verified["$ref"]="$sha"
done <<< "$verified_refs"
for index in "${!sources[@]}"; do
  target="${targets[$index]}"
  if [[ "${verified[$target]:-}" != "${expected_shas[$index]}" ]]; then
    echo "::error::Mirror SHA mismatch for $target" >&2
    exit 1
  fi
done

echo "MIRROR_VERIFIED=PASS refs=${#sources[@]} (no force, delete, or pruning)"
