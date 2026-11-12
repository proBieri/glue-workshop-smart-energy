---
description: Plan umsetzen, .tapp bauen, in den Emulator laden, testen (z.B. /build uc1)
agent: build
---

# /build — umsetzen, bauen, in den Emulator laden, testen

**Use Case: `$ARGUMENTS`** (leer → der Plan aus diesem Chat; ohne Plan der erste rote Use Case)

Steht kein Plan im Chat: zuerst kurz selbst planen (wie `/plan`), dann umsetzen.

## Ablauf

1. Skill `tasmota-berry` laden (ohne Skill-Werkzeug: `.opencode/skills/tasmota-berry/SKILL.md`);
   nur Funktionen verwenden, die dort stehen. WebUI/Heap: auch `tasmota-lowmem-webui`.
2. Code in `gplug/` schreiben, **genau eine Datei pro Use Case**: `uc0_basis.be` (Helfer, Puffer),
   `uc1_preise.be`, `uc2_zaehler.be`, `uc3_webui.be`, `uc4_csv.be`, `uc5_skript.be`,
   `uc6_befehle.be`, `main.be` (Treiberklasse mit `web_add_handler`, `web_add_main_button`,
   `web_sensor`, `save_before_restart`; Cron/Timer; Start — wird zuletzt geladen). Keine
   Aufteilung in `uc1a_…`, `uc1b_…`; keine zweite Puffer- oder Steuerdatei — Gemeinsames gehört
   in `uc0_basis.be`, Treiber/Cron/Start in `main.be`. Eine bestehende Datei erweitern, statt eine
   neue für dieselbe Aufgabe anzulegen. Dateien unter ~150 Zeilen.
3. Nach jeder Datei `bash build.sh`. Es muss enden mit
   `Emulator:  App geladen (http://emulator:8080)` und `=== Build OK ===`.
   `FEHLER … gplug/datei.be:ZEILE` → genau diese Stelle beheben, neu bauen.
4. `bash test.sh gplug ucN`, bis alle Tests dieses Use Case grün sind — **höchstens 3
   Reparaturversuche pro Test**. Ist derselbe Test danach noch rot: nicht weiter probieren, sondern
   anhalten, Schritt 6 ausführen und berichten (Test, `datei.be:zeile`, Vermutung). Nur die App
   ändern, nie `spec/` (auch nicht die Testblöcke). Fehler lesen: `spec/README.md`, Abschnitt
   *Abnahmetests* — die Meldung des Tests nennt oft schon die Ursache. Zeigt `test.sh`
   `STOPP: UCx-N ist zum 3. Mal in Folge rot`: sofort anhalten (Schritt 6, berichten).
5. `bash test.sh` — Use Cases, die vorher grün waren, müssen grün bleiben. Rote Tests eines
   **anderen** Use Case, die schon vor dieser Sitzung rot waren, nicht reparieren, sondern in der
   Meldung nennen. Hängt ein Test dieses Use Case an einem solchen Fehler: einmal ansehen; nicht
   gefunden → berichten.
6. **Zum Schluss immer `bash build.sh`** — auch wenn noch Tests rot sind. Danach liegen
   `build/gplug.tapp` (für den gPlug) und die neue App im Emulator (<http://localhost:8080/emu>).
   Meldet `build.sh` `Emulator: keiner … erreichbar`: anhalten und melden, dass der Emulator nicht
   läuft (Person am Notebook: `docker compose up -d emulator`).

## Regeln

- BKW-Antwort: `demo_eintraege` aus dem Skill unverändert übernehmen (nur umbenennen), kein eigener
  Parser. Puffer (Tarife, Einspeisung, Bezug): `demo_puffer`/`demo_wert`/`demo_setzen`/`demo_anzahl`
  aus dem Skill übernehmen (nur umbenennen, einmal in `uc0_basis.be`) — nie byteweise selbst lesen. `chart.json`: `p`/`e`/`b` = Base64 der int16-Puffer (`tob64()`), keine JSON-Listen.
- Ein Namensraum: Globals mit Präfix (`ucN_`, `gplug_`), jeden Namen vor der ersten Verwendung
  definieren; in Funktionen jede Variable mit `var` (strict).
- Tests sind kein Vorbild: `_emu_*` und `T.*` gibt es nur im Emulator. Zeitzonen-Offset:
  `tasmota.rtc()["local"] - tasmota.rtc()["utc"]`.
- Debuggen vom Stacktrace aus (`gplug/<datei>.be:<zeile>`), höchstens eine Runde `log("GPL: …")`,
  im selben Schritt wie der Fix wieder entfernen.
- **Nie Dateien löschen, verschieben oder zurücksetzen** (`rm`, `mv`, `git checkout`/`restore`/`reset`
  sind gesperrt), nie `build/` leeren — `build.sh` schreibt alles neu. Dateien nur mit edit/write ändern.
- Kompilierfehler (`FEHLER … gplug/datei.be:ZEILE`): nur diese Stelle und die Zeilen davor ansehen
  (fehlendes/überzähliges `end`, `var`, Klammer). Den Compiler, `build.sh` oder den Emulator nicht
  untersuchen, keine Dateien zum Eingrenzen weglegen — die Meldung stimmt.
- Specs: `spec/uc1-preise.md`, `uc2-zaehler.md`, `uc3-webui.md`, `uc4-csv.md`,
  `uc5-zaehlerschluessel.md`, `uc6-befehle.md` — keine anderen Namen raten. `referenz/` und
  `emulator/` sind leer: nicht lesen.
- **`gplug/gplug_ui.html` ist vorgegeben** (Kacheln, Grafik, Tooltip): nicht ändern, kein HTML/JavaScript
  schreiben, nie als Berry-Strings. `web_add_main_button()` liest sie aus der `.tapp` und sendet sie in Stücken.
- Start vor NTP: erst mit `tasmota.rtc()["utc"] > 1700000000` abrufen oder Puffer schieben, und das wiederholt
  prüfen (Timer), nicht nur einmal (UC1-9/10).
- Eigene Erweiterung über die Spec hinaus: Code + Zeile in der Testtabelle der Spec + Test.

## Meldung (fünf Zeilen)

Was geändert · welche Tests grün/rot · `build/gplug.tapp` gebaut und im Emulator geladen (ja/nein)
· was offen · nächster Schritt (`/new`, dann `/plan ucN+1`).
