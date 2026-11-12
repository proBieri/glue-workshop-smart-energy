# UC4: Tagesabrechnung als CSV pro Monat

## Beschreibung

Kurz nach Mitternacht (00:01) hängt die App für den Vortag eine Zeile an
die Monatsdatei `/gplug_JJJJ-MM.csv` an (Monat des Vortags). Nach einem
Neustart wird ein verpasster Tagesabschluss nachgeholt. Die Datei lässt
sich über Tasmotas Dateiverwaltung herunterladen und in Excel öffnen.

## Format

```
Datum;Einspeisung_kWh;Verguetung_CHF;Bezug_kWh;Luecken_h
2026-11-12;16.019;2.09;8.066;0.00
```

| Spalte | Berechnung |
|---|---|
| `Einspeisung_kWh` | Σ Einspeisung der 96 Viertelstunden, 3 Nachkommastellen |
| `Verguetung_CHF` | Σ Viertelstunde (Einspeisung kWh × Einspeisetarif CHF/kWh), 2 Nachkommastellen; negativ, wenn bei negativem Tarif eingespeist wurde |
| `Bezug_kWh` | Σ Bezug, 3 Nachkommastellen |
| `Luecken_h` | Stunden ohne Einspeise- oder Tarifwert = Viertelstunden / 4, 2 Nachkommastellen (z.B. `0.25`) |

Trennzeichen `;`, Dezimalpunkt `.`, Zeilenende `\n`, Kopfzeile beim Anlegen.

Keine Kosten für den Bezug: Einspeisetarif ≠ Bezugstarif, und den Bezugstarif kennen
wir nicht. „Kosten“ entstehen nur, wenn bei negativem Einspeisetarif eingespeist wird —
sie sind in `Verguetung_CHF` enthalten (negative Viertelstunden).

## Randbedingungen

- Jeder Tag genau einmal, auch über Neustarts (UC4-4, UC4-8).
- Tage ganz ohne Messwerte (z.B. vor dem ersten Start) erzeugen keine Zeile.
- Höchstens `csv_monate` (Standard 3, `/gplug.json`) Dateien: ältere `gplug_JJJJ-MM.csv` werden gelöscht.
- Die Datei wird nur ergänzt, nie ganz neu geschrieben (Flash, Heap).

## Tests

| ID | Test | Erwartung |
|---|---|---|
| UC4-1 | nach 00:05 | `/gplug_2026-11.csv` mit Kopfzeile und Zeile für den Starttag |
| UC4-2 | voller Tag 12.11. | 5 Spalten (keine Kosten); Einspeisung/Bezug = Zählerdifferenz 00:00–00:00 (±0.002 kWh); `Luecken_h` = 0.00 |
| UC4-3 | Vergütung | = Σ `e`×`p` von gestern (Index 0–95) aus `chart.json` (±0.011) |
| UC4-4 | 5 h später | Zeile für 12.11. genau einmal |
| UC4-5 | alte Dateien Juli–Oktober vorhanden | Juli und August gelöscht, September und Oktober bleiben |
| UC4-6 | Tag vor dem Start | keine Zeile |
| UC4-7 | Zähler 13.11. 12:00:30–14:00:30 aus | `Luecken_h` = 2.25 (12:00–14:15, 9 Viertelstunden) |
| UC4-8 | Gerät über Mitternacht aus (Neustart 23:55, Uhr erst 00:05 gültig) | Zeile für den Vortag wird nach dem Start nachgeholt, genau einmal |
| UC4-9 | `/gplug.json` mit `csv_monate` = 1 | nach dem Abschluss bleibt nur die Datei des laufenden Monats |

### Abnahmetests (ausführbar)

Jeder `berry`-Block unten ist ein Abnahmetest und läuft in einem **frischen Emulator** (`bash test.sh gplug ucN`). Hilfsfunktionen `T.*`: `spec/README.md`. Die App korrigieren, nie diese Blöcke — sie ändern sich nur zusammen mit der Tabelle oben.

<details><summary>Testcode (2 Blöcke)</summary>

```berry
# UC4 — Tagesabrechnung als CSV pro Monat

import string

var KOPF = "Datum;Einspeisung_kWh;Verguetung_CHF;Bezug_kWh;Luecken_h"

# alte Monatsdateien anlegen (csv_monate = 3 → Juli und August werden gelöscht)
for m: ["07", "08", "09", "10"]
  T.schreiben("/gplug_2026-" + m + ".csv", KOPF + "\n")
end

var eo0
var ei0
var eo1
var ei1
var chart

def zeile(datum)
  var s = T.datei("/gplug_2026-11.csv")
  if s == nil return nil end
  for l: string.split(s, "\n")
    if string.startswith(l, datum) return string.split(l, ";") end
  end
  return nil
end

T.test("UC4-1 Nach Mitternacht entsteht die Monatsdatei mit Kopfzeile", def ()
  T.bis(0, 0)
  eo0 = T.eo_wh()
  ei0 = T.ei_wh()
  T.bis(0, 5)
  var s = T.datei("/gplug_2026-11.csv")
  T.check(s != nil, "/gplug_2026-11.csv fehlt")
  T.eq(string.split(s, "\n")[0], KOPF, "Kopfzeile")
  T.check(zeile("2026-11-11") != nil, "Zeile für den Starttag 2026-11-11")
end)

T.test("UC4-2 Ein voller Tag: Einspeisung und Bezug = Zählerdifferenz", def ()
  T.bis(0, 0)
  eo1 = T.eo_wh()
  ei1 = T.ei_wh()
  T.bis(0, 5)
  chart = T.chart()
  var z = zeile("2026-11-12")
  T.check(z != nil, "Zeile 2026-11-12 fehlt")
  T.eq(size(z), 5, "Anzahl Spalten (keine Kosten: Bezugstarif unbekannt)")
  T.nahe(real(z[1]), (eo1 - eo0) / 1000.0, 0.002, "Einspeisung_kWh")
  T.nahe(real(z[3]), (ei1 - ei0) / 1000.0, 0.002, "Bezug_kWh")
  T.eq(real(z[4]), 0.0, "Luecken_h bei vollständigem Tag")
end)

T.test("UC4-3 Vergütung = Σ Viertelstunde (Einspeisung × Tarif)", def ()
  var z = zeile("2026-11-12")
  var chf = 0.0
  for i: 0 .. 95                      # gestern = 12.11.
    var e = chart['e'][i]
    var p = chart['p'][i]
    T.check(e != nil && p != nil, "12.11. Viertelstunde " + str(i) + " ohne Einspeisung oder Tarif")
    if e != nil && p != nil chf += e / 1000.0 * p / 10000.0 end
  end
  T.nahe(real(z[2]), chf, 0.011, "Verguetung_CHF")
end)

T.test("UC4-4 Jeder Tag steht genau einmal in der Datei", def ()
  T.stunden(5)
  var n = 0
  for l: string.split(T.datei("/gplug_2026-11.csv"), "\n")
    if string.startswith(l, "2026-11-12") n += 1 end
  end
  T.eq(n, 1, "Zeilen für 2026-11-12")
end)

T.test("UC4-5 Es bleiben höchstens 3 Monatsdateien", def ()
  var namen = T.dateien()
  T.check(namen.find("gplug_2026-07.csv") == nil, "Juli nicht gelöscht")
  T.check(namen.find("gplug_2026-08.csv") == nil, "August nicht gelöscht")
  T.check(namen.find("gplug_2026-09.csv") != nil, "September gelöscht (zu früh)")
  T.check(namen.find("gplug_2026-10.csv") != nil, "Oktober gelöscht (zu früh)")
end)

T.test("UC4-6 Tage ganz ohne Messwerte (vor dem ersten Start) erzeugen keine Zeile", def ()
  T.check(zeile("2026-11-10") == nil, "Zeile für 2026-11-10 (vor dem Start) vorhanden")
end)

T.test("UC4-7 Luecken_h zählt Viertelstunden ohne Einspeisung", def ()
  T.bis(12, 0, 30)
  T.zaehler_an(false)
  T.bis(14, 0, 30)
  T.zaehler_an(true)
  T.bis(0, 5)
  var z = zeile("2026-11-13")
  T.check(z != nil, "Zeile 2026-11-13 fehlt")
  T.nahe(real(z[4]), 2.25, 0.001, "Luecken_h (12:00–14:15 ohne Einspeisewert)")
end)
```

```berry
# UC4 — verpasster Tagesabschluss wird nachgeholt; csv_monate aus /gplug.json
# T.neustart(600): die Uhr ist erst 10 min nach dem Start gültig — um 00:01 weiss die App
# noch nicht, dass ein neuer Tag ist, und muss den Abschluss nach dem Start nachholen.

import string

T.schreiben("/gplug_2026-10.csv", "Datum;Einspeisung_kWh;Verguetung_CHF;Bezug_kWh;Luecken_h\n")
T.schreiben("/gplug.json", '{"csv_monate":1}')

def anzahl(datum)
  var s = T.datei("/gplug_2026-11.csv")
  if s == nil return 0 end
  var n = 0
  for l: string.split(s, "\n")
    if string.startswith(l, datum) n += 1 end
  end
  return n
end

T.test("UC4-8 Verpasster Tagesabschluss wird nach dem Start nachgeholt", def ()
  T.bis(23, 55)
  T.neustart(600)
  T.bis(0, 20)
  T.eq(anzahl("2026-11-11"), 1, "Zeilen für 2026-11-11 (nach dem Start nachgeholt)")
  T.stunden(2)
  T.eq(anzahl("2026-11-11"), 1, "Zeilen für 2026-11-11 (nicht doppelt)")
end)

T.test("UC4-9 csv_monate aus /gplug.json: es bleibt nur der laufende Monat", def ()
  T.check(T.dateien().find("gplug_2026-10.csv") == nil, "Oktober nicht gelöscht (csv_monate = 1)")
  T.check(T.dateien().find("gplug_2026-11.csv") != nil, "November fehlt")
end)
```

</details>
