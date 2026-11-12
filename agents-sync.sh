#!/usr/bin/env bash
# agents-sync.sh — hält Befehle und Skills für opencode und Claude Code synchron
#
#   .opencode/commands/  <->  .claude/commands/
#   .opencode/skills/    <->  .claude/skills/
#
# Abgleich in beide Richtungen: Fehlt eine Datei auf einer Seite, wird sie
# kopiert; unterscheiden sich beide, gewinnt die neuere (Änderungszeit).
# Löschen wird NICHT übertragen — eine Datei auf beiden Seiten löschen.
#
#   ./agents-sync.sh            abgleichen
#   ./agents-sync.sh --quiet    abgleichen, nur Änderungen melden
#   ./agents-sync.sh --check    nur prüfen; Exit 1, wenn nicht synchron
#
# Läuft automatisch: Claude-Code-Hook (.claude/settings.json), build.sh,
# Git-Pre-Commit-Hook (.githooks/pre-commit, aktivieren mit
# `git config core.hooksPath .githooks`).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MODE="sync"
QUIET=0
for a in "$@"; do
  case "$a" in
    --check) MODE="check" ;;
    --quiet) QUIET=1 ;;
    *) echo "Unbekannte Option: $a" >&2; exit 2 ;;
  esac
done

A=".opencode"
B=".claude"
DIRS="commands skills"
diffs=0

say() { [ "$QUIET" -eq 1 ] || echo "$@"; }

copy() {   # copy <quelle> <ziel>
  mkdir -p "$(dirname "$2")"
  cp -p "$1" "$2"
  echo "agents-sync: $1 → $2"
}

for d in $DIRS; do
  # Vereinigung der relativen Pfade beider Seiten
  # Fehlt der Ordner auf einer Seite, wird er beim Kopieren angelegt
  files=$( { if [ -d "$A/$d" ]; then (cd "$A/$d" && find . -type f ! -name .DS_Store); fi; \
             if [ -d "$B/$d" ]; then (cd "$B/$d" && find . -type f ! -name .DS_Store); fi; } | sort -u )
  for rel in $files; do
    rel="${rel#./}"
    fa="$A/$d/$rel"
    fb="$B/$d/$rel"
    if [ -f "$fa" ] && [ -f "$fb" ] && cmp -s "$fa" "$fb"; then
      continue
    fi
    diffs=$((diffs + 1))
    if [ "$MODE" = "check" ]; then
      if [ ! -f "$fa" ]; then echo "agents-sync: fehlt $fa"
      elif [ ! -f "$fb" ]; then echo "agents-sync: fehlt $fb"
      else echo "agents-sync: verschieden $fa <-> $fb"; fi
      continue
    fi
    if [ ! -f "$fb" ]; then copy "$fa" "$fb"
    elif [ ! -f "$fa" ]; then copy "$fb" "$fa"
    elif [ "$fb" -nt "$fa" ]; then copy "$fb" "$fa"
    else copy "$fa" "$fb"
    fi
  done
done

if [ "$MODE" = "check" ]; then
  if [ "$diffs" -gt 0 ]; then
    echo "agents-sync: $diffs Datei(en) nicht synchron — ./agents-sync.sh ausführen" >&2
    exit 1
  fi
  say "agents-sync: .opencode und .claude sind synchron"
else
  say "agents-sync: $diffs Datei(en) abgeglichen"
fi
