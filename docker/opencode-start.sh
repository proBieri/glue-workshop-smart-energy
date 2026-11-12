#!/usr/bin/env bash
# opencode-start.sh — Startet opencode im Container mit Infomaniak AI Tools
#
# Werte kommen aus .env (siehe .env.example):
#   INFOMANIAK_API_KEY      API-Token (Infomaniak Manager → AI Tools → API-Token)
#   INFOMANIAK_PRODUCT_ID   ID des AI-Tools-Produkts (steht in der Manager-URL)
#   INFOMANIAK_MODEL        Modell-ID, Standard Qwen/Qwen3.5-397B-A17B-FP8 (Liste: "modelle")
#   INFOMANIAK_BASE_URL     optional, Standard: OpenAI-kompatibler v2-Endpunkt
#   INFOMANIAK_CONTEXT      optional, Kontextfenster für opencode (Standard 80000; Qwen3.5-397B kann 200000)
#   INFOMANIAK_OUTPUT       optional, max. Ausgabe-Tokens pro Antwort (Standard 16384)
#   INFOMANIAK_THINKING     optional, "on" = Modell denkt vor jeder Antwort (Standard: aus)
#   OPENCODE_STEPS          optional, max. Schritte pro Auftrag (Standard 120) — Kostenbremse
#
# Gemessen 31.10.2026 (Kimi-K2.6 bei Infomaniak, ~25 Tokens/s): mit Denken
# 106–190 s pro kleiner Aufgabe, oft nur Denk-Tokens; ohne Denken ~20 s mit
# brauchbarem Berry-Code. Build und Tests fangen die verbleibenden Fehler.
#
# Ohne Limits fordert opencode bei unbekannten Modellen fast das ganze
# Kontextfenster als Ausgabe an — Infomaniak antwortet dann mit HTTP 400.
#
#   docker compose run --rm opencode            opencode im Repo starten
#   docker compose run --rm opencode modelle    verfügbare Modelle anzeigen
#   docker compose run --rm opencode bash       Shell im Container
#   docker compose up opencode-web   Weboberfläche (http://localhost:4096)

set -euo pipefail

BASE="${INFOMANIAK_BASE_URL:-https://api.infomaniak.com/2/ai/${INFOMANIAK_PRODUCT_ID:-}/openai/v1}"

if [ "${1:-}" = "modelle" ]; then
  : "${INFOMANIAK_API_KEY:?INFOMANIAK_API_KEY fehlt in .env}"
  : "${INFOMANIAK_PRODUCT_ID:?INFOMANIAK_PRODUCT_ID fehlt in .env}"
  curl -fsS -H "Authorization: Bearer ${INFOMANIAK_API_KEY}" "${BASE}/models" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(m.get("id")) for m in d.get("data", d if isinstance(d, list) else [])]'
  exit 0
fi

# Weboberfläche: opencode als Dienst im Container, Anmeldung per Einmal-Link
if [ "${1:-}" = "link" ]; then
  exec opencode pair --url "http://localhost:${OPENCODE_WEB_PORT:-4096}"
fi

if [ "${1:-}" = "bash" ]; then
  shift
  exec bash "$@"
fi

# opencode-Konfiguration aus .env erzeugen (der Schlüssel bleibt in der Umgebung)
if [ -n "${INFOMANIAK_API_KEY:-}" ]; then
  : "${INFOMANIAK_PRODUCT_ID:?INFOMANIAK_PRODUCT_ID fehlt in .env}"
  : "${INFOMANIAK_MODEL:?INFOMANIAK_MODEL fehlt in .env — Liste mit: docker compose run --rm opencode modelle}"
  mkdir -p /root/.config/opencode
  BASE="$BASE" python3 - <<'PY'
import json, os
model = os.environ["INFOMANIAK_MODEL"]
# Kimi-K2.6 kann bei Infomaniak 249984 Tokens. Wir melden opencode bewusst
# weniger: dann fasst opencode den Verlauf früher zusammen. Gemessen (UC1, 85
# Schritte): der Kontext wuchs auf 125k Tokens und wurde bei jedem Schritt neu
# bezahlt (5.4 Mio. Eingabe-Tokens). Mit 80k bleibt jeder Schritt deutlich kleiner.
# opencode 2.2.x fasst vor jedem Schritt zusammen, sobald der Verlauf
#   context − max(15 % von context, 16000) Tokens
# erreicht (keep: die letzten ~15k bleiben wörtlich). 80000 → ab 64000 Tokens.
# Mit dem früheren Standard 249984 lag die Schwelle bei 212487 — darum gab es in
# den Sessions vom 01.11.2026 (bis 185k Tokens) nie eine Zusammenfassung.
# Geprüft 02.11.2026 mit INFOMANIAK_CONTEXT=12000: 4× compaction "auto" bei Kimi.
limit = {"context": int(os.environ.get("INFOMANIAK_CONTEXT") or 80000),
         "output": int(os.environ.get("INFOMANIAK_OUTPUT") or 16384)}
thinking = (os.environ.get("INFOMANIAK_THINKING") or "off").lower() in ("on", "1", "true", "ja")
steps = int(os.environ.get("OPENCODE_STEPS") or 120)
# vLLM-Chat-Template: Kimi nutzt "thinking", Qwen "enable_thinking". Mistral-Modelle
# lehnen chat_template_kwargs ab (HTTP 400 "chat_template is not supported for
# Mistral tokenizers", geprüft 02.11.2026) — dort ohne diese Option.
model_options = {} if model.lower().startswith("mistralai/") else \
    {"chat_template_kwargs": {"thinking": thinking, "enable_thinking": thinking}}
cfg = {
    "$schema": "https://opencode.ai/config.json",
    "provider": {
        "infomaniak": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "Infomaniak AI Tools",
            "options": {"baseURL": os.environ["BASE"], "apiKey": "{env:INFOMANIAK_API_KEY}"},
            "models": {model: {"name": model, "limit": limit, "tool_call": True, "options": model_options}},
        }
    },
    "model": "infomaniak/" + model,
    "small_model": "infomaniak/" + model,
    # Kostenbremsen — gemessen 01.11.2026: Kimi machte pro Auftrag bis 218
    # Schritte, jeder mit bis zu 182k Tokens Verlauf (62 Mio. Eingabe-Tokens,
    # ~17 CHF für UC1). Nach `steps` Schritten muss der Agent anhalten und
    # berichten; man kann dann gezielt weitermachen.
    "agent": {a: {"steps": steps} for a in ("build", "plan", "general")},
    # experimental.background_compaction + subagent_depth zusammen: opencode 2.2.4 antwortet nicht mehr (getestet)
    "compaction": {"auto": True},
    # Nur das Repo: gemessen 02.11.2026 las Kimi in zwei von drei Läufen fast nur
    # die Emulator-Kopie im Image (/opt/gplug/emulator/mock/emu.be) statt mit
    # log("GPL: …") zu debuggen. build.sh/test.sh nutzen sie weiter (Shell, nicht Werkzeug).
    # Kein Löschen/Verschieben/Zurücksetzen per Shell — gemessen 12.11.2026: Qwen hat bei
    # einem Kompilierfehler `rm -rf build/*`, `rm gplug/main.be` und `mv gplug/… /tmp/`
    # ausgeführt (Datei mit dem Container verloren). Dateien ändert der Agent mit edit/write.
    "permission": {
        "external_directory": "deny",
        "bash": {"*": "allow", **{c: "deny" for c in (
            "rm", "rm *", "rmdir *", "mv *", "unlink *", "shred *", "truncate *", "find * -delete*",
            "git checkout *", "git restore *", "git clean *", "git reset *", "git stash *",
            "git rm *", "git mv *")}},
    },
    # Berry-Sprache und Tasmota-API: Skill tasmota-berry (.opencode/skills/), nicht im
    # Systemprompt — die frühere BERRY_LANGUAGE_REFERENCE.txt ist seit 11.11.2026 im Skill.
}
with open("/root/.config/opencode/opencode.json", "w") as f:
    json.dump(cfg, f, indent=2)
print(f"opencode: Infomaniak, Modell {model}, Denken {'an' if thinking else 'aus'}, max. {steps} Schritte pro Auftrag")
PY
  [ -t 1 ] && sleep 2      # sichtbar lassen, bevor die opencode-Oberfläche den Bildschirm übernimmt
else
  echo "Hinweis: INFOMANIAK_API_KEY ist nicht gesetzt — opencode startet mit eigener Anbieterwahl (/connect)."
fi

# Im Container ohne Hintergrunddienst arbeiten: mit dem Dienst hing "opencode run"
# reproduzierbar (getestet mit opencode 2.2.4), mit --standalone nicht.
if [ "${1:-}" = "web" ]; then
  opencode serve --service --hostname 0.0.0.0 --port 4096 &
  SRV=$!
  until curl -s -o /dev/null http://127.0.0.1:4096/; do sleep 1; done
  echo
  echo "opencode-Weboberfläche: http://localhost:${OPENCODE_WEB_PORT:-4096}"
  echo "Anmelden mit dem Link unten (einmalig gültig, 5 Minuten). Neuer Link:"
  echo "  docker compose exec opencode-web opencode-start link"
  echo "Dann: Projekt hinzufügen → /workshop/ eingeben → Enter → Ordner auswählen."
  opencode pair --url "http://localhost:${OPENCODE_WEB_PORT:-4096}" | grep -E "http|Links"
  wait $SRV
  exit $?
fi

case "${1:-}" in
  ""|-*) exec opencode --standalone "$@" ;;
  run)   shift; exec opencode run --standalone "$@" ;;
  *)     exec opencode "$@" ;;
esac
