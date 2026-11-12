# gPlug-App „Vergütung 2027“ — Spezifikation

Eine Tasmota-Berry-App für den gPlug (ESP32-C3, kein PSRAM). Sie holt die
dynamischen Einspeisetarife der BKW, erfasst pro Viertelstunde Einspeisung und
Bezug am Smart Meter, zeigt gestern, heute und morgen als Grafik im Tasmota-WebUI
(1 SVG-Einheit pro Viertelstunde, auf die Breite skaliert) und
schreibt jeden Tag eine Abrechnungszeile in eine CSV-Datei pro Monat.

## Use Cases

| ID | Name | Pflicht | Testblöcke |
|---|---|---|---|
| [UC1](uc1-preise.md) | Einspeisetarife der BKW abrufen | ja | 3 (Abruf, Netzwerkfehler, Start vor NTP) |
| [UC2](uc2-zaehler.md) | Einspeisung und Bezug pro Viertelstunde erfassen, laufende Viertelstunde live | ja | 3 (Zähler, Neustart mit Stand 0, `/gplug.json`) |
| [UC3](uc3-webui.md) | Momentanwerte + 3-Tage-Grafik im WebUI (Oberfläche `gplug/gplug_ui.html` vorgegeben) | ja | 2 (mit Tarifen, ohne Tarife) |
| [UC4](uc4-csv.md) | Tagesabrechnung als CSV pro Monat | ja | 2 (Abrechnung, Nachholen nach Neustart) |
| [UC5](uc5-zaehlerschluessel.md) | Zählerschlüssel automatisch aus dem SML-Skript | Zusatz | 2 (Skript, Konfiguration) |
| [UC6](uc6-befehle.md) | Tasmota-Befehle `GplugInfo`, `GplugPreise`, `GplugAbruf` — nur wenn Zeit bleibt | Zusatz, zuletzt | 1 |

## Abnahmetests

Die Tests stehen **in den Specs**: unter jeder Testtabelle ein oder mehrere
```` ```berry ````-Blöcke (auf GitHub eingeklappt unter „Testcode“). Jede Zeile `UCx-N` der Tabelle entspricht einem
`T.test("UCx-N …")` darin. Die Tests prüfen nur, was von aussen sichtbar ist (HTTP,
Sensorzeilen, Befehle, Dateien) — jede Umsetzung, die diese Verträge einhält, besteht
sie. **Die App korrigieren, nie die Testblöcke** — sie ändern sich nur zusammen mit
ihrer Tabelle.

```bash
bash test.sh                  # alle Tests gegen gplug/ (baut vorher)
bash test.sh gplug uc1        # nur spec/uc1*.md
bash test.sh referenz         # Referenzlösung, muss immer grün sein
```

Ohne `berry` (Mensch oder Agent direkt auf dem Notebook): `docker compose run --rm tools bash test.sh`.
Der Gesamtlauf enthält die Zusätze UC5/UC6; wer sie nicht umsetzt, prüft `uc1` bis `uc4` einzeln.
Fertig bei `=== Testblöcke: N bestanden, 0 fehlgeschlagen ===`.

**Testumgebung:** Jeder Block läuft in einem frischen Emulator: Mi 11.11.2026 10:00 MEZ,
leeres Dateisystem, BKW-API als Fixture, simulierter Zähler `{"z":{"Ei":…,"Eo":…}}`. Die
Zeit läuft nur über `T.bis`, `T.stunden`, `T.sekunden`; Cron und Timer feuern dabei exakt.
Die App startet beim ersten `T`-Aufruf, der sie braucht (Zeit, Web, Befehl, Dateien lesen,
Abrufe) — was ein Block davor einstellt (`T.netz`, `T.schreiben`, `T.zaehler_…`), gilt also
schon beim Start, wie auf dem Gerät.

**Hilfsfunktionen `T`** (gibt es nur im Emulator, nie im App-Code — `build.sh` lehnt sie ab;
die Emulator-Dateien selbst nicht lesen):

- Zeit: `T.bis(hh,mm[,ss])`, `T.stunden(n)`, `T.sekunden(n)`, `T.jetzt()`, `T.heute()`
- Web: `T.hauptseite()`, `T.sensor()`, `T.http(pfad)` → `{code,mime,body}`, `T.json(pfad)`,
  `T.chart()` (`chart.json` mit dekodierten Listen `p`/`e`/`b`, `nil` = leer)
- Befehle (nur UC6): `T.cmd("GplugInfo")`
- Dateien: `T.datei(name)`, `T.dateien()`, `T.schreiben(name,text)`
- Zähler: `T.eo_wh()`, `T.ei_wh()`, `T.zaehler_an(bool)`, `T.zaehler_null(bool)` (alle Werte 0 wie Tasmota-SML vor dem ersten Telegramm),
  `T.zaehler_sprung(ei_wh, eo_wh)` (Stand springt: negativ = Zählertausch, gross = Messfehler), `T.zaehler_tarife(an[, namen, in_wh])`
  (Tarifregister statt Ei/Eo, Standardnamen Ei1/Ei2/Eo1/Eo2, `in_wh` = Werte in Wh;
  `eo_wh`/`ei_wh` bleiben Summen)
- Netz: `T.netz("error"|"fixture")`, `T.abrufe()`
- Neustart: `T.neustart(uhr_ab)` — App neu laden wie beim Booten (Dateisystem bleibt); die ersten `uhr_ab` Sekunden liefert `tasmota.rtc()` nur die Sekunden seit dem Start (vor NTP)
- Prüfungen: `T.eq`, `T.nahe`, `T.check`, `T.enthaelt`

**Fehler lesen:**

- `FEHLER UCx-N …` nennt die Erwartung; `chart.json (spec/uc3-webui.md): …` beschreibt ein
  falsches Format — im genannten Spec-Abschnitt nachlesen.
- Zeilennummern stimmen: `spec/uc1-preise.md:142` ist Zeile 142 der Spec (Testcode),
  `gplug/<datei>.be:<zeile>` nach `BRY: Exception>` ist die Stelle in der App — genau dort
  lesen und beheben.
- Kein Fehler, aber falsches Ergebnis (`0 Abrufe`, Wert `0`/`nil`, Route 404): **eine** Runde
  `log("GPL: …")` an den Entscheidungsstellen, dann
  `bash test.sh gplug ucN 2>&1 | grep -E "GPL:|FEHLER"`; die Logs mit dem Fix wieder entfernen.
- Derselbe Test nach 3 Versuchen noch rot: anhalten und berichten (Test, Datei:Zeile, Vermutung).

**Live im Emulator** (im Agent-Container `$EMU_URL` = `http://emulator:8080`; die Person am
Notebook sieht dasselbe unter <http://localhost:8080/emu>):

```bash
curl -s "$EMU_URL/cm?cmnd=GplugInfo"                          # Befehl wie auf dem Gerät
curl -s "$EMU_URL/?m=1"                                       # Sensorzeilen (web_sensor)
curl -s "$EMU_URL/gplug/chart.json"                           # eigene Route
curl -s -X POST "$EMU_URL/emu/api/advance" -d '{"s":3600}'    # Uhr 1 h vorspulen
curl -s "$EMU_URL/emu/api/log?seit=0" | tail -c 2000          # Log inkl. BRY:-Exceptions
```

## Abhängigkeiten

Die Tests eines Use Case brauchen nur ihn selbst und die **früheren** Use Cases
(Reihenfolge UC1 … UC6). Gemeinsame Schnittstellen (`chart.json`, Daten-`div` `gp_d`)
stehen darum in jeder Spec, soweit sie dort schon nötig sind. Die Befehle (`Gplug*`, UC6)
kommen zuletzt und sind freiwillig — **kein Test in UC1–UC5 benutzt sie**.

```
UC1 Tarife ──┐
             ├──> UC3 Grafik
UC2 Zähler ──┤
             └──> UC4 CSV
UC5 Zählerschlüssel aus dem Skript ── erweitert UC2  (Zusatz)
UC6 Befehle ── liest UC1/UC2 (+ UC5)           (Zusatz, zuletzt)
```

## Gemeinsame Regeln

- **Zeit**: gerechnet wird in lokaler Zeit (`tasmota.rtc()["local"]`), Tag = lokale Epoch / 86400. Die BKW-API liefert UTC.
- **Ohne Zeitsynchronisation** (`tasmota.rtc()["utc"]` < 1 700 000 000) passiert nichts.
- **Konfiguration** `/gplug.json` (optional, beim Start gelesen — Änderungen gelten nach einem Neustart; fehlt sie oder ist sie kaputt, gelten die Standardwerte):

  | Schlüssel | Standard | Bedeutung |
  |---|---|---|
  | `key_ein` | – | JSON-Schlüssel des Einspeisezählers in `Status 10`, mehrere mit `+` summiert (UC2); ohne Eintrag `Eo` bzw. `Eo1 + Eo2 …` |
  | `key_bez` | – | JSON-Schlüssel des Bezugszählers, wie `key_ein` (UC2); ohne Eintrag `Ei` bzw. `Ei1 + Ei2 …` |
  | `einheit` | `"kWh"` | Einheit dieser Zählerstände: `"kWh"` oder `"Wh"` (UC2) |
  | `csv_monate` | `3` | so viele Monatsdateien bleiben erhalten |

- **Kein Absturz**: Netzwerk-, Zähler- und Dateifehler werden geloggt, die App läuft weiter.
- **Keine Kosten für den Bezug**: Die BKW-API liefert den Einspeisetarif, nicht den Bezugstarif. Den kennen wir nicht — Bezug erscheint nur als Energie (kWh).

## RAM-Budget (ESP32-C3, ~105 kB frei, davon nutzt Tasmota schon einen Teil)

| Datenstruktur | Grösse | Art |
|---|---|---|
| Tarife: 3 Tage × 96 Viertelstunden × 2 Byte | 576 B | fix |
| Einspeisung + Bezug: 2 × 3 × 96 × 2 Byte | 1152 B | fix |
| Code der App | ~15–20 kB | fix |
| BKW-Antwort beim Abruf | ~2 kB (gestreamt in eine Datei, 1-kB-Stücke) | flüchtig, einmal pro Tag |
| `gplug_ui.html` (vorgegeben) beim Seitenaufruf | ~8.2 kB, in 2-kB-Stücken gesendet | flüchtig |
| `chart.json` (Base64 der Puffer) | ~2 kB | flüchtig, alle 5 min |


## Mockups

`mockups/` enthält Entwürfe der Grafik (Juni- und Oktober-Daten).
