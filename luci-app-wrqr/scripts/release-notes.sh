#!/bin/sh
#
# template: release-notes v3 (repo-templates)
# Formatted to pass both `shfmt -i 2` and `shfmt -i 2 -bn -ci`, the styles
# the consuming repositories check with; each gets this file verbatim.
# Do not edit in place: change templates/shared/ in repo-templates
# and run scripts/sync-templates.sh --update.
#
# Print release notes for a tag, built from the subjects of the commits since
# the previous release tag. There is no changelog file: the commit subject is
# the release note, so write it as the line a user should read.
#
# A commit whose subject is only a version number ("Release 1.2.0",
# "release: v0.2.0") says nothing a user can read and is left out.
#
# A commit that touches only documentation, CI, tests or checks is listed
# under "Documentation and tooling" rather than "Changes".
#
# Usage: scripts/release-notes.sh <tag> [previous-tag]
#
# The previous tag defaults to the nearest v* tag before <tag>. For a final
# release, pre-release tags (_rc, _beta, _alpha) are skipped, so its notes
# cover everything since the last final release rather than since its RC. The repository
# for the compare link comes from GITHUB_REPOSITORY, or from the origin remote.
# Needs the full history: check out with fetch-depth 0.

set -eu

[ $# -ge 1 ] || {
  printf 'usage: %s <tag> [previous-tag]\n' "$0" >&2
  exit 2
}

tag="$1"
if [ $# -ge 2 ]; then
  previous="$2"
elif printf '%s\n' "$tag" | grep -Eq '_(rc|beta|alpha)'; then
  previous="$(git describe --tags --abbrev=0 --match 'v*' "$tag^" 2>/dev/null || true)"
else
  previous="$(git describe --tags --abbrev=0 --match 'v*' --exclude '*_rc*' \
    --exclude '*_beta*' --exclude '*_alpha*' "$tag^" 2>/dev/null || true)"
fi

repository="${GITHUB_REPOSITORY:-}"
if [ -z "$repository" ]; then
  url="$(git remote get-url origin 2>/dev/null || true)"
  url="${url%.git}"
  repository="$(printf '%s\n' "$url" | sed -n 's#.*github\.com[:/]\(.*\)$#\1#p')"
fi

if [ -n "$previous" ]; then
  range="$previous..$tag"
else
  range="$tag"
fi

# Subjects that carry nothing but a version number.
bump='^(release|bump|version)[: ]+(to )?v?[0-9]+(\.[0-9]+)*([-_][a-z0-9]+)?$'

# Paths that never change what a user runs.
tooling='^(docs/|\.github/|tests?/|scripts/(check|test|gen|ci)-|scripts/release-notes\.sh$|LICENSE|NOTICE|THIRD_PARTY|.*\.md$|\.[^/]+$)'

changes=""
tooling_changes=""
for commit in $(git rev-list --no-merges --reverse "$range"); do
  subject="$(git log -1 --format=%s "$commit")"
  if printf '%s\n' "$subject" | grep -Eiq "$bump"; then
    continue
  fi
  paths="$(git diff-tree --no-commit-id --name-only -r --root "$commit")"
  if printf '%s\n' "$paths" | grep -Evq "$tooling"; then
    changes="$changes- $subject
"
  else
    tooling_changes="$tooling_changes- $subject
"
  fi
done

if [ -n "$changes" ]; then
  printf '## Changes\n\n%s' "$changes"
fi
if [ -n "$tooling_changes" ]; then
  [ -z "$changes" ] || printf '\n'
  printf '## Documentation and tooling\n\n%s' "$tooling_changes"
fi
if [ -z "$changes$tooling_changes" ]; then
  printf 'Version update only; no other changes since %s.\n' "$previous"
fi

if [ -n "$repository" ]; then
  if [ -n "$previous" ]; then
    printf '\n**Full diff**: https://github.com/%s/compare/%s...%s\n' \
      "$repository" "$previous" "$tag"
  else
    printf '\n**Full history**: https://github.com/%s/commits/%s\n' \
      "$repository" "$tag"
  fi
fi
