#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

filter_wiki_paths() {
  while IFS= read -r line; do
    if [[ "$line" == wiki/* ]]; then
      printf '%s\n' "$line"
    fi
  done
}

print_paths() {
  local label="$1"
  shift
  local -a paths=("$@")

  printf '%s: %d\n' "$label" "${#paths[@]}"
  if ((${#paths[@]} > 0)); then
    printf '  %s\n' "${paths[@]}"
  fi
}

check_shapes() {
  local folder="$1"
  local label="$2"
  shift 2
  local -a required=("$@")
  local -a files=()
  local outline=""
  local file=""
  local -a missing=()
  local checked=0
  local issues=0

  mapfile -t files < <(obsidian files folder="$folder" ext=md || true)

  for file in "${files[@]}"; do
    if [[ -z "$file" ]]; then
      continue
    fi

    checked=$((checked + 1))
    outline="$(obsidian outline path="$file" format=json)"
    missing=()

    for heading in "${required[@]}"; do
      if ! jq -e --arg heading "$heading" 'any(.[]; .heading == $heading)' <<<"$outline" >/dev/null; then
        missing+=("$heading")
      fi
    done

    if ((${#missing[@]} > 0)); then
      local missing_text
      missing_text="$(printf '%s, ' "${missing[@]}")"
      missing_text="${missing_text%, }"
      printf 'Schema issue: %s missing [%s]\n' "$file" "$missing_text"
      issues=$((issues + 1))
      failures=$((failures + 1))
    fi
  done

  printf '%s files checked: %d, issues: %d\n' "$label" "$checked" "$issues"
}

check_frontmatter() {
  local folder="$1"
  local label="$2"
  local expected_type="$3"
  shift 3
  local -a required=("$@")
  local -a files=()
  local properties=""
  local property=""
  local file=""
  local -a missing=()
  local checked=0
  local issues=0

  mapfile -t files < <(obsidian files folder="$folder" ext=md || true)

  for file in "${files[@]}"; do
    if [[ -z "$file" ]]; then
      continue
    fi

    checked=$((checked + 1))
    properties="$(obsidian properties path="$file" format=json 2>/dev/null || true)"

    if ! jq -e 'type == "object"' <<<"$properties" >/dev/null 2>&1; then
      printf 'Schema issue: %s missing YAML frontmatter\n' "$file"
      issues=$((issues + 1))
      failures=$((failures + 1))
      continue
    fi

    missing=()
    for property in "${required[@]}"; do
      if ! jq -e --arg property "$property" '
        has($property)
        and .[$property] != null
        and .[$property] != ""
        and (if (.[$property] | type) == "array" then (.[$property] | length) > 0 else true end)
      ' <<<"$properties" >/dev/null 2>&1; then
        missing+=("$property")
      fi
    done

    if ! jq -e --arg expected_type "$expected_type" '.type == $expected_type' <<<"$properties" >/dev/null 2>&1; then
      missing+=("type=$expected_type")
    fi

    if ((${#missing[@]} > 0)); then
      local missing_text
      missing_text="$(printf '%s, ' "${missing[@]}")"
      missing_text="${missing_text%, }"
      printf 'Schema issue: %s missing/invalid [%s]\n' "$file" "$missing_text"
      issues=$((issues + 1))
      failures=$((failures + 1))
    fi
  done

  printf '%s files checked: %d, issues: %d\n' "$label" "$checked" "$issues"
}

require_command obsidian
require_command jq

failures=0

printf 'Vault path: %s\n' "$(obsidian vault info=path)"

# Raw sources are immutable copies and may include upstream wikilinks that do not
# belong to this vault, so unresolved-link health should ignore entries that come
# only from sources/files/ while still checking maintained notes under wiki/ and
# the root operational docs.
wiki_unresolved="$(obsidian unresolved counts verbose format=json | jq '
  def source_paths:
    if .sources == null then []
    elif (.sources | type) == "array" then .sources
    else [(.sources | tostring)]
    end;
  [
    .[]
    | select(source_paths | any(startswith("sources/files/") | not))
  ]
')"
wiki_unresolved_count="$(jq 'length' <<<"$wiki_unresolved")"
printf 'Wiki unresolved links: %s\n' "$wiki_unresolved_count"
if ((wiki_unresolved_count > 0)); then
  jq -r '.[] | "  " + .link + " <- " + (.sources | tostring)' <<<"$wiki_unresolved"
  failures=$((failures + 1))
fi

mapfile -t wiki_orphans < <(obsidian orphans all | filter_wiki_paths)
print_paths 'Wiki orphans' "${wiki_orphans[@]}"
if ((${#wiki_orphans[@]} > 0)); then
  failures=$((failures + 1))
fi

mapfile -t wiki_deadends < <(obsidian deadends all | filter_wiki_paths)
print_paths 'Wiki dead ends' "${wiki_deadends[@]}"
if ((${#wiki_deadends[@]} > 0)); then
  failures=$((failures + 1))
fi

check_frontmatter 'wiki/sources' 'Source note frontmatter' 'source' \
  source_slug \
  local_file

check_frontmatter 'wiki/inspections' 'Inspection frontmatter' 'inspection' \
  repo \
  question \
  scope_paths

check_shapes 'wiki/sources' 'Source note schema' \
  'Summary' \
  'Key Takeaways' \
  'Implications For This Wiki' \
  'Related Pages'

check_shapes 'wiki/inspections' 'Inspection schema' \
  'Question' \
  'Answer' \
  'Trace' \
  'Evidence' \
  'Uncertainty' \
  'Related Pages'

check_shapes 'wiki/concepts' 'Concept schema' \
  'Definition' \
  'Why It Matters' \
  'Supporting Evidence' \
  'Related Pages' \
  'Open Questions'

check_shapes 'wiki/entities' 'Entity schema' \
  'Definition' \
  'Why It Matters' \
  'Supporting Evidence' \
  'Related Pages' \
  'Open Questions'

check_shapes 'wiki/syntheses' 'Synthesis schema' \
  'Question' \
  'Answer' \
  'Evidence' \
  'Follow-Ups' \
  'Related Pages'

if ((failures == 0)); then
  printf 'Wiki health: PASS\n'
  exit 0
fi

printf 'Wiki health: FAIL (%d issue groups)\n' "$failures" >&2
exit 1
