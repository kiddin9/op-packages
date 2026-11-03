#!/bin/sh
#
# template: check-readme v1 (repo-templates)
# Formatted to pass both `shfmt -i 2` and `shfmt -i 2 -bn -ci`, the styles
# the consuming repositories check with; each gets this file verbatim.
# Do not edit in place: change templates/shared/ in repo-templates
# and run scripts/sync-templates.sh --update.
#
# Hold README.md (English) and README.ru.md (Russian) to the shared layout:
#
#   # <Product> for <platform>        # <Product> для <platform>
#   [Русский](README.ru.md)           [English](README.md)
#   badges: CI, Release, License
#   ## Features                       ## Возможности
#   ## Requirements                   ## Требования
#   ## Installation                   ## Установка
#   ## <project sections>             ## <project sections>
#   ## Development                    ## Разработка
#   ## Documentation                  ## Документация
#   ## Support                        ## Поддержка
#   ## License                        ## Лицензия
#
# Both files must have the same number of sections, so one language cannot
# silently drop what the other says. Punctuation is plain ASCII in both: no
# typographic dashes, arrows, quotes or ellipses. The release badge is required
# only where .github/workflows/release.yml exists. Every relative link must
# resolve.

set -eu

root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

status=0
fail() {
  printf 'README: %s\n' "$*" >&2
  status=1
}

headings() {
  sed -n 's/^## //p' "$1"
}

# check_layout <file> <first three sections> <last four sections>, each list
# separated by '|'. Project sections may only sit between the two.
check_layout() {
  file="$1"
  head_want="$2"
  tail_want="$3"
  if [ ! -f "$file" ]; then
    fail "$file is missing"
    return
  fi
  if ! head -n 1 "$file" | grep -q '^# '; then
    fail "$file does not start with a '# ' title"
  fi
  head_have="$(headings "$file" | head -n 3 | paste -sd '|' -)"
  tail_have="$(headings "$file" | tail -n 4 | paste -sd '|' -)"
  if [ "$head_have" != "$head_want" ]; then
    fail "$file: the first sections are '$head_have', expected '$head_want'"
  fi
  if [ "$tail_have" != "$tail_want" ]; then
    fail "$file: the last sections are '$tail_have', expected '$tail_want'"
  fi
}

check_layout README.md 'Features|Requirements|Installation' \
  'Development|Documentation|Support|License'
check_layout README.ru.md 'Возможности|Требования|Установка' \
  'Разработка|Документация|Поддержка|Лицензия'

if ! grep -qF '[Русский](README.ru.md)' README.md; then
  fail 'README.md does not link to README.ru.md'
fi
if ! grep -qF '[English](README.md)' README.ru.md; then
  fail 'README.ru.md does not link to README.md'
fi

en="$(headings README.md | wc -l | tr -d ' ')"
ru="$(headings README.ru.md | wc -l | tr -d ' ')"
if [ "$en" != "$ru" ]; then
  fail "README.md has $en sections and README.ru.md has $ru"
fi

for file in README.md README.ru.md; do
  if ! grep -q 'actions/workflows/.*badge\.svg' "$file"; then
    fail "$file has no CI badge"
  fi
  if ! grep -q 'img\.shields\.io/github/license\|License-\|license-' "$file"; then
    fail "$file has no license badge"
  fi
  if [ -f .github/workflows/release.yml ]; then
    if ! grep -q 'img\.shields\.io/github/v/release' "$file"; then
      fail "$file has no release badge"
    fi
  fi

  # The curly quotes in the pattern are what it looks for, not a typo.
  # shellcheck disable=SC1112
  typographic="$(grep -n '—\|–\|→\|←\|«\|»\|“\|”\|‘\|’\|…' "$file" | head -n 3 || true)"
  if [ -n "$typographic" ]; then
    fail "$file has non-ASCII punctuation: $typographic"
  fi

  # Relative links: [text](path) and [text](path#anchor), not URLs or anchors.
  links="$(grep -o '](\([^)#:]*\)[)#]' "$file" | sed 's/^](//; s/[)#]$//' | sort -u)"
  missing=""
  for target in $links; do
    [ -e "$target" ] || missing="$missing $target"
  done
  [ -z "$missing" ] || fail "$file links to missing files:$missing"
done

[ "$status" -eq 0 ] && printf 'README layout OK: %s sections each\n' "$en"
exit "$status"
