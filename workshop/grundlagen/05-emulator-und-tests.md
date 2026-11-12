# 5 · Emulator und Tests

Auf dem gPlug zu entwickeln ist langsam (hochladen, neu starten) und riskant
(ein Speicherfehler startet das Gerät neu). Darum läuft die App zuerst im
**Emulator** — derselbe Berry-Compiler wie auf dem Gerät (Tasmota 15.3.0),
die Tasmota-Funktionen nachgebildet.

## Was nachgebildet ist

| Gerät | Emulator |
|---|---|
| Tasmota-Hauptseite mit `/?m=1`-Poll | gleiche Mechanik, `http://localhost:8080/` |
| Konsole, `/cm?cmnd=…` | Bedienfeld-Konsole und `/cm?cmnd=…` (`Status 10`, `Br …`, eigene Befehle) |
| Uhr, Cron, Timer | virtuelle Uhr mit Zeitraffer (bis 3600×) und Sprüngen; Cron feuert exakt |
| Smart Meter | Simulator: `{"z":{"Ei":…,"Eo":…,"Pi":…,"Po":…}}` mit PV-Tagesgang |
| BKW-API | **live** (echte API) oder **Fixture** (simulierter Tag), oder **Netzwerkfehler** |
| Dateisystem | `emulator/fs/` (CSV ansehen und herunterladen) |
| `.tapp`-Dateien | `tasmota.wd` zeigt auf `build/` |

Grenzen: Heap-Zahlen sind Schätzungen (Desktop hat 64-bit-Zeiger), es gibt kein
MQTT, keine Regeln, und Desktop-Berry kennt Module (`os`, `time`), die auf dem
Gerät fehlen.

## Bedienfeld

```bash
docker compose up -d emulator            # → http://localhost:8080/emu
```

Startest du einen Agenten (`docker compose run --rm opencode`), läuft der Emulator
automatisch mit. Der Agent erreicht ihn als `http://emulator:8080`. Sobald
`build/autoexec.be` neu gebaut ist, lädt der Emulator die App von selbst neu.

- **Neu bauen & laden**: führt `./build.sh` aus und startet die App neu
- **Neustart**: wie `Restart 1` — Dateisystem und `persist` bleiben
- **Zurücksetzen**: Dateisystem leeren, Uhr auf jetzt
- **Zeit**: Pause, 1×–3600×, +1 h, +1 Tag, „bis 18:06“, „bis 00:02“
- **Smart Meter**: abschalten (Ausfall testen), PV-Leistung ändern
- **BKW-API**: `auto` (live, solange die Uhr stimmt), `fixture`, `error`

Referenzlösung ansehen: `docker compose up -d referenz` → <http://localhost:8090/emu>

## Tests

```bash
docker compose run --rm tools bash test.sh             # alle Tests gegen gplug/
docker compose run --rm tools bash test.sh gplug uc2   # nur UC2
docker compose run --rm tools bash test.sh referenz    # Referenzlösung
```

Jeder Testblock (```` ```berry ```` in `spec/ucN-*.md`, auf GitHub unter „Testcode“ eingeklappt) startet einen frischen Emulator am **Mi 11.11.2026 10:00**. Ein Test
spult die Zeit vor und prüft dann von aussen:

```berry
T.test("UC1-4 Ab 18 Uhr werden die Tarife für morgen geholt — genau einmal", def ()
  var n = T.abrufe()
  T.bis(18, 10)                                  # Zeit vorspulen, Cron läuft
  T.eq(T.abrufe(), n + 1, "Abrufe bis 18:10")
  var d = T.json("/gplug/chart.json")            # Schnittstelle aus der Spec
  …
end)
```

| Hilfsfunktion | |
|---|---|
| `T.bis(hh, mm)`, `T.stunden(n)`, `T.sekunden(n)` | Zeit vorspulen |
| `T.hauptseite()`, `T.sensor()`, `T.http(pfad)`, `T.json(pfad)` | WebUI abfragen |
| `T.cmd("GplugInfo")` | Befehl ausführen (nur in UC6) |
| `T.datei("/x.csv")`, `T.dateien()`, `T.schreiben(n, s)` | Dateisystem |
| `T.eo_wh()`, `T.ei_wh()`, `T.zaehler_an(false)`, `T.zaehler_sprung(ei, eo)`, `T.zaehler_tarife(…)` | Zähler-Simulator (Ausfall, Zählertausch, Tarifregister) |
| `T.neustart(uhr_ab)` | App neu laden wie beim Booten, Uhr erst nach `uhr_ab` s gültig |
| `T.netz("error")`, `T.abrufe()` | BKW-API |
| `T.eq`, `T.nahe`, `T.check`, `T.enthaelt` | Prüfungen |

Ausgabe: `OK` oder `FEHLER` mit Erwartung und Ergebnis; `BRY: Exception>`-Zeilen zeigen
Laufzeitfehler der App mit Stacktrace.
