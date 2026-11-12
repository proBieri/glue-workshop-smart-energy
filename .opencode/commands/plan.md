---
description: Einen Use Case planen, nur lesen (z.B. /plan uc1)
agent: plan
---

# /plan — einen Use Case planen

**Use Case: `$ARGUMENTS`** (leer → der erste, dessen Tests noch rot sind; Reihenfolge uc1 … uc6)

Nur lesen, keine Datei ändern, nichts bauen. Der Plan steht im Chat; `/build` setzt ihn danach
in derselben Sitzung um.

1. Skill `tasmota-berry` laden (ohne Skill-Werkzeug: `.opencode/skills/tasmota-berry/SKILL.md`).
   Für UC3 (WebUI, Grafik) zusätzlich `tasmota-lowmem-webui`.
2. Lesen: `spec/README.md` und die Spec dieses Use Case (mit den Testblöcken unten), genau diese
   Namen, keine anderen raten: uc1 `spec/uc1-preise.md` · uc2 `spec/uc2-zaehler.md` ·
   uc3 `spec/uc3-webui.md` · uc4 `spec/uc4-csv.md` · uc5 `spec/uc5-zaehlerschluessel.md` ·
   uc6 `spec/uc6-befehle.md`. `referenz/` und `emulator/` sind leer. Bestehende
   Dateien in `gplug/` nur, soweit der Plan darauf aufbaut (`grep -n` statt ganze Dateien).
3. Plan, **höchstens 40 Zeilen, kein Code**:
   - Dateien in `gplug/`: `uc0_basis.be` (Helfer, Puffer), **eine** Datei `ucN_<name>.be` für diesen
     Use Case (`uc1_preise`, `uc2_zaehler`, `uc3_webui`, `uc4_csv`, `uc5_skript`, `uc6_befehle`),
     `main.be` (Treiber, Cron, Start) — keine Aufteilung in `ucNa_…`, `ucNb_…`
   - Datenstrukturen mit Grösse (`bytes()`-Puffer, int16, Marker für „leer“)
   - verwendete Tasmota-Funktionen — nur solche aus dem Skill
   - Zeitplan (Cron/Timer) und Start vor NTP (`rtc()["utc"] > 1700000000` wiederholt prüfen, UC1-9/10)
   - UC3: `gplug/gplug_ui.html` ist vorgegeben — nur der Berry-Teil wird geplant
   - welcher Test `UCx-N` durch welchen Schritt grün wird
4. Fallen prüfen: BKW-Antwort mit `write_file()` + `demo_eintraege` aus dem Skill (kein
   `json.load`, kein `get_string()`), `chart.json` mit Base64 (`tob64()`), keine `_emu_*`/`T.*`.

Am Schluss: „Plan fertig. Weiter mit `/build ucN`.“
