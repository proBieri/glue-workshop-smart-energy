#!/usr/bin/env bash
# test.sh — App bauen und die Abnahmetests aus spec/ im Emulator ausführen
#
#   docker compose run --rm tools bash test.sh               # eigene App (gplug/)
#   docker compose run --rm tools bash test.sh referenz      # Referenzlösung
#   docker compose run --rm tools bash test.sh gplug uc1     # nur spec/uc1*.md
#
# Die Tests stehen als ```berry-Blöcke in spec/ucN-*.md (unter der Testtabelle).
# Jeder Block läuft in einem frischen Emulator (Start: Mi 11.11.2026 10:00,
# leeres Dateisystem, BKW-API als Fixture). Exit-Code 1, wenn ein Test fehlschlägt.
#
# Zeilennummern: jeder Block wird in eine eigene Datei gezogen, alle anderen Zeilen
# bleiben leer — "Zeile 42" in einer Fehlermeldung ist Zeile 42 der Spec-Datei.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

case "${1:-gplug}" in
  referenz) SRC="referenz/gplug"; OUT="build/referenz" ;;
  *)        SRC="${1:-gplug}";    OUT="build" ;;
esac
FILTER="${2:-}"
EMU="${EMU_DIR:-emulator}"     # in den Agent-Containern: /opt/gplug/emulator (im Image)

bash build.sh "$SRC" "$OUT"
echo

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ```berry-Blöcke herausziehen: eine Datei pro Block, gleiche Zeilennummern wie die Spec.
# Ausgabe pro Block: "<spec-datei> <block-nr> <anzahl> <block-datei>"
bloecke() {
  python3 - "$TMP" "$@" <<'PY'
import os, sys
tmp = sys.argv[1]
for md in sys.argv[2:]:
    zeilen = open(md, encoding="utf-8").read().split("\n")
    bereiche, start = [], None
    for i, z in enumerate(zeilen):
        s = z.strip()
        if start is None and s == "```berry":
            start = i + 1
        elif start is not None and s == "```":
            bereiche.append((start, i)); start = None
    if start is not None:
        sys.exit(f"FEHLER: {md}: ```berry-Block ab Zeile {start} nicht geschlossen")
    name = os.path.splitext(os.path.basename(md))[0]
    for k, (a, b) in enumerate(bereiche, 1):
        datei = os.path.join(tmp, f"{name}_{k}.be")
        with open(datei, "w", encoding="utf-8") as f:
            f.write("\n".join(z if a <= i < b else "" for i, z in enumerate(zeilen)) + "\n")
        print(md, k, len(bereiche), datei)
PY
}

ok=0
fail=0
liste="$(bloecke spec/${FILTER}*.md)"
[ -n "$liste" ] || { echo "FEHLER: keine Tests (\`\`\`berry-Blöcke) in spec/${FILTER}*.md" >&2; exit 1; }
while read -r md k n t; do
  fs="$TMP/fs_$(basename "$t" .be)"
  mkdir -p "$fs"
  echo "--- $md, Testblock $k von $n"
  # sed: Blockdatei → Spec-Datei; quelle.py: "build/autoexec.be:212" → "gplug/uc1_preise.be:57"
  if berry -m "$EMU/mock" "$EMU/testrunner.be" "$OUT/autoexec.be" "$fs" "$t" "$EMU/mock" 2>&1 </dev/null \
       | sed "s|$t|$md|g" | python3 "$EMU/quelle.py" "$OUT/autoexec.be" | tee -a "$TMP/log"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
  echo
done <<< "$liste"

# Stopp-Zähler: wie oft war ein Test hintereinander rot (über mehrere test.sh-Aufrufe)?
# Gemessen 12.11.2026: Qwen hat UC2-4 über zehnmal rot gesehen und weiter probiert —
# die Stopp-Regel im Prompt allein reicht nicht. Grün oder > 20 min alt → zurück auf 0.
if [ "$SRC" != "referenz/gplug" ]; then
  python3 - "$TMP/log" "$ROOT/.rote_tests.json" <<'PY' || true
import json, re, sys, time
log, datei = sys.argv[1], sys.argv[2]
try:
    z = json.load(open(datei))
except Exception:
    z = {}
jetzt = time.time()
stopp = []
for zeile in open(log, encoding="utf-8", errors="replace"):
    m = re.match(r"\s+(OK|FEHLER)\s+(UC\d+-\d+\w*)", zeile)
    if not m:
        continue
    st, tid = m.groups()
    alt = z.get(tid, {"n": 0, "t": 0})
    if st == "OK" or jetzt - alt["t"] > 1200:
        alt = {"n": 0, "t": jetzt}
    if st == "FEHLER":
        alt = {"n": alt["n"] + 1, "t": jetzt}
        if alt["n"] >= 3:
            stopp.append((tid, alt["n"]))
    z[tid] = alt
json.dump(z, open(datei, "w"))
for tid, n in stopp:
    print(f"STOPP: {tid} ist zum {n}. Mal in Folge rot — nicht weiter probieren. "
          "Anhalten, bash build.sh, berichten: Test, datei.be:zeile, Vermutung.")
PY
fi

echo "=== Testblöcke: $ok bestanden, $fail fehlgeschlagen ==="
[ "$fail" -eq 0 ]
