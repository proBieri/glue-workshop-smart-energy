#!/usr/bin/env bash
# build.sh — gPlug-App bauen: Berry-Quellen → autoexec.be → Kompilierprüfung → .tapp
#
# Aufruf (im Container, dort ist der Berry-Compiler installiert):
#   docker compose run --rm tools bash build.sh                       # gplug/ → build/
#   docker compose run --rm tools bash build.sh referenz/gplug build/referenz
#
# Schritte:
#   1. Alle *.be der Quelle alphabetisch zusammenfügen, main.be immer zuletzt
#      (ein gemeinsamer Namensraum: Globals brauchen eindeutige Präfixe)
#   2. Übrige Dateien (z.B. gplug_ui.html) mitkopieren
#   3. Mit dem Berry-Compiler aus Tasmota 15.3 übersetzen (Syntax, unbekannte Namen)
#   4. Als .tapp packen (unkomprimiertes ZIP mit autoexec.be)
#   5. In den laufenden Emulator laden (falls einer für dieses Build-Verzeichnis läuft)
#
# Bricht mit Exit-Code 1 ab, wenn etwas nicht stimmt — es gibt keinen
# "Erfolg" ohne echte Kompilierung.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-gplug}"
OUT="${2:-build}"
cd "$ROOT"

if [ ! -d "$SRC" ]; then
  echo "FEHLER: Quellverzeichnis '$SRC' fehlt" >&2
  exit 1
fi
if ! command -v berry >/dev/null 2>&1; then
  echo "FEHLER: Berry-Compiler nicht gefunden. Im Container ausführen:" >&2
  echo "  docker compose run --rm tools bash build.sh $*" >&2
  exit 1
fi

shopt -s nullglob
SOURCES=()
for f in "$SRC"/*.be; do
  [ "$(basename "$f")" = "main.be" ] || SOURCES+=("$f")
done
if [ -f "$SRC/main.be" ]; then
  SOURCES+=("$SRC/main.be")
fi
if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "FEHLER: keine .be-Dateien in '$SRC'" >&2
  exit 1
fi

# Befehle/Skills für opencode und Claude Code synchron halten (siehe agents-sync.sh)
bash agents-sync.sh --quiet || true

echo "=== gPlug Build: $SRC → $OUT ==="
# Nur die eigenen Dateien löschen, keine Unterordner: build/referenz/ (Referenz-Emulator :8090)
# liegt in build/ — ein "rm -rf build" beim Bauen der eigenen App löschte sie mit.
mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -type f -delete
APP="$OUT/autoexec.be"

# --- 1. Zusammenfügen; die Markierungszeilen braucht compile.be für Fehlermeldungen
{
  echo "# autoexec.be — automatisch erzeugt von build.sh aus $SRC/ ($(date '+%Y-%m-%d %H:%M'))"
  for f in "${SOURCES[@]}"; do
    echo "#@@ $f"
    cat "$f"
    echo
  done
} > "$APP"
echo "  Module:    ${#SOURCES[@]} (${SOURCES[*]##*/})"

# --- 2. Weitere Dateien der App (nicht .be, nicht versteckt)
EXTRA=()
for f in "$SRC"/*; do
  case "$f" in *.be) continue ;; esac
  [ -f "$f" ] || continue
  cp "$f" "$OUT/"
  EXTRA+=("$(basename "$f")")
done
[ ${#EXTRA[@]} -gt 0 ] && echo "  Dateien:   ${EXTRA[*]}"

# --- 2b. Verbotene Namen: kompilieren im Emulator, fehlen aber auf dem gPlug
python3 - "${SOURCES[@]}" <<'PY'
import re, sys
regeln = [
    (r"\b_emu_\w*", "nur im Emulator/in den Tests vorhanden, nicht auf dem gPlug (Zeitzonen-Offset: tasmota.rtc()[\"local\"] - tasmota.rtc()[\"utc\"])"),
    (r"(?<![\w.])T\.[a-z]\w*\(", "T.* ist das Testwerkzeug der Spec-Tests (spec/), nicht Teil der App"),
    (r"(?<![\w.])float\(", "gibt es in Berry nicht -> real()"),
    (r"(?<![\w.])len\(", "gibt es in Berry nicht -> size()"),
    (r"tasmota\.(http_get|timer_set|webserver|file_read|file_write|flag_get|sensor_read)\b", "gibt es nicht (Skill tasmota-berry, 'Diese Funktionen gibt es NICHT')"),
    (r"(?<![\w.])import\s+(os|time)\b", "Modul gibt es nur im Emulator, nicht auf dem gPlug"),
]
KEYWORDS = {"return", "raise", "except", "import", "if", "elif", "while", "for", "and", "or", "not", "as", "def", "var", "else", "end", "true", "false", "nil"}
fehler = 0
for f in sys.argv[1:]:
    zeilen = open(f, encoding="utf-8").read().splitlines()
    if len(zeilen) > 150:
        print(f"WARNUNG: {f}: {len(zeilen)} Zeilen (Richtwert 150) — Agenten verlieren bei grossen Dateien den Überblick; aufteilen", file=sys.stderr)
    for nr, zeile in enumerate(zeilen, 1):
        # Name direkt vor einem String ohne +: Berry liest `s = s "x"` als `s = s` und verwirft "x"
        roh = re.sub(r'"(?:[^"\\]|\\.)*"', '"S"', zeile)
        roh = re.sub(r"'(?:[^'\\]|\\.)*'", "'S'", roh).split("#", 1)[0]
        m = re.search(r"(?:[=(,+]|^)\s*([A-Za-z_]\w*(?:\[[^\]]*\])?)\s+[\"']", roh)
        if m and m.group(1) not in KEYWORDS:
            print(f"FEHLER: {f}:{nr}: '{m.group(1)} \"…\"' — fehlendes +; Berry verwirft den String stillschweigend (s = s \"x\" ergibt s). Richtig: s += \"x\" oder s = s + \"x\"", file=sys.stderr)
            fehler += 1
        code = zeile.split("#", 1)[0] if '"' not in zeile and "'" not in zeile else zeile
        if code.lstrip().startswith("#"):
            continue
        for muster, grund in regeln:
            m = re.search(muster, code)
            if m:
                print(f"FEHLER: {f}:{nr}: '{m.group(0)}' — {grund}", file=sys.stderr)
                fehler += 1
if fehler:
    sys.exit(1)
PY

# --- 3. Kompilieren (gegen die Tasmota-Globals des Emulators)
# EMU_DIR: in den Agent-Containern liegt der Emulator im Image (/opt/gplug/emulator)
EMU="${EMU_DIR:-emulator}"
berry -m "$EMU/mock" "$EMU/compile.be" "$APP" "$EMU/mock"

# --- 4. .tapp packen (ZIP ohne Kompression, wie Tasmota es verlangt)
python3 - "$OUT" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
tapp = os.path.join(out, "gplug.tapp")
files = ["autoexec.be"] + sorted(f for f in os.listdir(out)
                                 if f not in ("autoexec.be", "gplug.tapp") and not f.startswith("."))
with zipfile.ZipFile(tapp, "w", compression=zipfile.ZIP_STORED) as z:
    for f in files:
        z.write(os.path.join(out, f), f)
print(f"  Paket:     {tapp} ({os.path.getsize(tapp)} Byte: {', '.join(files)})")
PY

# --- 5. In den laufenden Emulator laden (wie das Hochladen auf den gPlug)
# Der Emulator, dessen Build-Verzeichnis $OUT ist, startet die App neu und meldet,
# ob sie geladen wurde. Läuft keiner, ist das kein Fehler.
python3 - "$OUT" "${EMU_URL:-}" <<'PY'
import json, sys, urllib.request
out, eigen = sys.argv[1], sys.argv[2]
urls = [eigen] if eigen else []
urls += ["http://emulator:8080", "http://referenz:8080", "http://localhost:8080", "http://localhost:8090"]
for url in dict.fromkeys(urls):
    try:
        req = urllib.request.Request(url + "/emu/api/laden", data=json.dumps({"build": out}).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=20 if url == eigen else 3) as r:
            a = json.load(r)
    except Exception:
        continue
    if a.get("ok") is None:
        continue                      # Emulator für ein anderes Build-Verzeichnis
    if a["ok"]:
        print(f"  Emulator:  App geladen ({url})")
        sys.exit(0)
    print(f"FEHLER: Emulator ({url}) konnte die App nicht laden:", file=sys.stderr)
    for z in a.get("log", []):
        print("  " + z, file=sys.stderr)
    sys.exit(1)
print(f"  Emulator:  keiner für {out}/ erreichbar — nicht geladen (docker compose up -d emulator)")
PY

echo "=== Build OK ==="
