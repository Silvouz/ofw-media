#!/usr/bin/env bash
# Remove from the published site (branch main) the media of posts that have gone out, so the
# GitHub Pages site stays well under its 1 GB limit. Run by promote.yml after the promotion.
#
# Rule: a file in videos/ is removed PRUNE_AFTER_DAYS (14) days after it reached main. Nothing reaches
# main more than about 10 days before its due date (host_media.sh --due sends later posts to the stock
# branch and promote.yml moves them 9 days ahead), so every file outlives its post by at least 4 days.
# videos/KEEP (optional, one slug per line) protects the media of a post moved to a later date after its
# files went live; remove the line once that post has gone out.
#
# Works in a blobless, sparse clone (no video is downloaded). DRY_RUN=1 lists without changing anything,
# DRY_RUN=2 also commits locally without pushing.
set -euo pipefail
DAYS=${PRUNE_AFTER_DAYS:-14}
cutoff=$(date -u -d "-$DAYS days" +%s)
keep=$(git show HEAD:videos/KEEP 2>/dev/null || true)
list=()
while IFS= read -r f; do
  case "$f" in *.mp4|*.jpg) ;; *) continue ;; esac
  slug=$(basename "$f" | sed -E 's/-[0-9a-f]{12}\.(mp4|jpg)$//')
  if [ -n "$keep" ] && grep -qxF "$slug" <<<"$keep"; then echo "kept (videos/KEEP): $f"; continue; fi
  added=$(git log --no-renames --diff-filter=A --format=%ct -1 HEAD -- "$f")
  if [ -n "$added" ] && [ "$added" -lt "$cutoff" ]; then list+=("$f"); fi
done < <(git ls-tree -r --name-only HEAD videos/)

if [ ${#list[@]} -eq 0 ]; then echo "nothing on the site for more than $DAYS days"; exit 0; fi
printf 'to remove: %s\n' "${list[@]}"
[ "${DRY_RUN:-0}" = 1 ] && exit 0

for i in 1 2 3; do
  if [ "${DRY_RUN:-0}" != 2 ]; then git fetch -q origin main && git reset -q --hard origin/main; fi
  todo=()
  for f in "${list[@]}"; do [ -n "$(git ls-tree --name-only HEAD -- "$f")" ] && todo+=("$f"); done
  if [ ${#todo[@]} -eq 0 ]; then echo "already removed"; exit 0; fi
  git rm -q --cached --sparse -- "${todo[@]}"
  git commit -qm "Remove media of posts that went out (on the site for more than $DAYS days)"
  [ "${DRY_RUN:-0}" = 2 ] && { echo "committed locally (DRY_RUN=2), not pushed"; exit 0; }
  if git push -q origin HEAD:main; then
    echo "removed ${#todo[@]} files"
    if [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
      gh api -X POST "repos/${GITHUB_REPOSITORY}/pages/builds" >/dev/null 2>&1 && echo "pages build requested" || true
    fi
    exit 0
  fi
  sleep 6
done
echo "push failed three times"; exit 1
