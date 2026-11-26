#!/bin/sh
set -e

CURFILE="current.txt"
[ -f "$CURFILE" ] || { echo "Falta $CURFILE"; exit 1; }

CUR="$(tr -d '\r\n' < "$CURFILE")"
[ -n "$CUR" ] || { echo "$CURFILE vacio"; exit 1; }

NEXT="$(printf '%s' "$CUR" | awk -F. 'BEGIN{OFS="."} {$NF=$NF+1; print}')"

git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ] && echo "Nada que commitear." && exit 0

printf '%s\n' "$NEXT" > "$CURFILE"
git add .
git commit -m "${1:-Update $NEXT}"
git tag "$NEXT"
git push
git push origin "$NEXT"

echo "Listo: $CUR -> $NEXT"
