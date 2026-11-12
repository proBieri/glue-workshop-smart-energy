# UC2: Einspeisung und Bezug pro Viertelstunde erfassen

## Beschreibung

Zu jeder Viertelstunde (:00, :15, :30, :45) liest die App die Zählerstände des
Smart Meters (Einspeisung und Bezug, kWh) und speichert die Differenz zur
letzten Ablesung als Energie der vergangenen Viertelstunde in Wh — gleiche
Auflösung wie die BKW-Tarife, eine SVG-Einheit pro Viertelstunde in der Grafik (UC3).
Jede Minute berechnet sie zusätzlich die **laufende Viertelstunde** (Stand seit
der letzten Ablesung) für Grafik und Sensorzeilen. Gespeichert wird nur die
abgeschlossene Viertelstunde.

## Datenquelle

`tasmota.read_sensors()` liefert dasselbe JSON wie `Status 10`, z.B.:

```json
{"Time":"2026-10-30T21:46:57","z":{"SMid":12345678,"Pi":847,"Po":0,
 "V1":228,"I1":2.82,"Ei":7654.321,"Eo":234.567,"rEi":12.345,"rEo":2345.678}}
```

| Schlüssel | Bedeutung | Einheit |
|---|---|---|
| `Eo` | Zählerstand Einspeisung (OBIS 2.8.0) | kWh |
| `Ei` | Zählerstand Bezug (OBIS 1.8.0) | kWh |
| `Po` / `Pi` | aktuelle Leistung Einspeisung / Bezug | W |

Zähler mit **Tarifregistern** liefern keinen Gesamtstand, sondern einen pro
Tarif, Leistungen dann oft in kW:

```json
{"z":{"SMid":"12345678","Pi":1.850,"Po":0.000,…,
 "Ei1":33994.217,"Ei2":9111.127,"Eo1":3.357,"Eo2":1.090}}
```

### Welche Schlüssel? (20 s nach dem Start festgelegt)

Jeder Zähler heisst anders — ohne passende Schlüssel bleiben auf dem Gerät Einspeisung, Bezug,
Vergütung und CSV leer, auch wenn alle Tests grün sind. Darum:

1. **`/gplug.json`** (beim Start gelesen, siehe `spec/README.md`), falls sie Schlüssel enthält:

   ```json
   {"key_ein": "Lief_HT+Lief_NT", "key_bez": "Bezug_HT+Bezug_NT", "einheit": "Wh"}
   ```

   `key_ein` / `key_bez` = JSON-Name in `Status 10`; mehrere mit `+` werden summiert.
   `einheit` = `"kWh"` (Standard) oder `"Wh"`, gilt für beide. Fehlt ein Schlüssel in der Datei,
   gilt für ihn Schritt 2 (UC2-11).
2. **Namenssuche:** `Eo` (Einspeisung) und `Ei` (Bezug) in kWh; fehlt der Schlüssel, die Summe
   der Tarifregister `Eo1 + Eo2 …` bzw. `Ei1 + Ei2 …` (UC2-7).

Die Schlüssel automatisch aus dem SML-Skript `/script.txt` erkennen ist der Zusatz **UC5**.

## Daten

| Feld | Typ | Grösse |
|---|---|---|
| Einspeisung pro Viertelstunde, 3 Tage × 96 | int16 in Wh, Marker 0x8000 = leer | 576 B |
| Bezug pro Viertelstunde, 3 Tage × 96 | int16 in Wh | 576 B |
| Letzte Ablesung (Wh, Zeit) | int | 12 B |
| Speicher für Neustart | `/gplug_zaehler.json`, jede Viertelstunde | ~2.4 kB Flash |

3 Tage = gestern, heute, morgen (wie die Tarife; für Einspeisung und Bezug bleibt
morgen leer). Der Tagesabschluss (UC4) um 00:01 braucht nur gestern.

## Randbedingungen

- Zählerstände **verlustfrei in Wh** rechnen — als 32-bit-float wäre 7654.321 kWh nur auf ±1 Wh genau.
- Nach dem Start wird nur die Basis gesetzt, keine Viertelstunde geschrieben. Eine gespeicherte Basis der laufenden Viertelstunde gilt weiter.
- Liegt die letzte Ablesung mehr als ~15 min zurück (Ausfall, Neustart; Grenze 1000 s), wird nur die Basis neu gesetzt — keine Energie mehrerer Viertelstunden in einer (UC2-3).
- Sinkt ein Zählerstand (Zählertausch) oder bringt eine Viertelstunde mehr als 20000 Wh (Messfehler), bleibt sie leer (UC2-10).
- Tasmota-SML meldet nach dem Start alle Werte als `0`, bis das erste Telegramm dekodiert ist. Ein Stand `0`, obwohl schon ein Stand > 0 bekannt ist, zählt als „kein Stand“ (UC2-9).
- **Laufende Viertelstunde:** jede Minute „Stand jetzt − Basis“ (auch `0`, UC2-6). Fehlt am **Ende** der Viertelstunde der Stand, wird sie wieder leer — sie war nicht vollständig (UC2-3). Nachts ist `0` richtig, nicht leer (UC2-4).
- **Mitternacht:** die Viertelstunde 23:45–24:00 wird um 00:00 abgeschlossen und gehört zu **gestern** (Index 95), nicht zu heute (191). Den Index aus dem **Beginn** der abgeschlossenen Viertelstunde (jetzt − 15 min) und dessen Tag berechnen (UC2-12).
- Zeitumstellung: der Tag hat immer 96 Plätze (Lücke bzw. Überschreiben in der Nacht).

## Schnittstellen, über die die Tests prüfen

Vertrag vollständig in `spec/uc3-webui.md`. Für UC2 nötig:

- **`GET /gplug/chart.json`**: zusätzlich zu `t`, `n`, `p` (UC1) die Felder `e` und `b` — je **Base64-Text**
  von 192 int16-Werten in Wh (`0x8000` = leer), Index 0–95 gestern, 96–191 heute (kein Morgen).
- **Daten-`div` in `web_sensor()`** (UC2-6), bei jedem Poll:
  `<div id='gp_d' style='display:none' data-v='{"p":2300,"e":3790,"b":4154,"v":0}'></div>` —
  `e`/`b` = Summe heute in Wh inkl. laufender Viertelstunde; `p`/`v` gehören zu UC1/UC3 (bis dahin `null`/`0`).

## Tests

Index in `chart.json`: heute = 96 + Viertelstunde (z.B. 11:00–11:15 → 96 + 44).

| ID | Test | Erwartung |
|---|---|---|
| UC2-1 | Zählerstand um 11:00 und 11:15 vergleichen | `e[96+44]` = Differenz in Wh (±2) |
| UC2-2 | Viertelstunden in der Zukunft | `e[96+53]` (13:15) leer; `e` hat nur 192 Werte (kein Morgen) |
| UC2-3 | Zähler liefert 12:00–14:00 nichts | 12:00–14:15 leer, kein Fehler (Ausfall > 15 min: keine Sammel-Viertelstunde); 15:00–15:15 wieder erfasst |
| UC2-4 | 01:15–01:30 (dunkel) | Wert `0`, nicht leer |
| UC2-5 | Bezugszähler um 05:00 und 05:15 vergleichen | `b[96+20]` = Differenz in Wh (±2) |
| UC2-6 | um 07:22 (laufende Viertelstunde) | `b[96+29]` ≥ Bezug 07:15–07:21; Momentanwert `b` im Daten-`div` |
| UC2-7 | Zähler liefert nur `Ei1`/`Ei2`, `Eo1`/`Eo2` | Bezug 05:00–05:15 und Einspeisung 11:00–11:15 = Differenz der Summen (±2 Wh) |
| UC2-9 | Neustart 23:59:45, Zähler meldet die erste Minute nur `0` | keine Viertelstunde 23:45–00:30 über 5000 Wh; 00:15–00:30 korrekt (±2 Wh) |
| UC2-10 | 11:05 sinkt der Einspeisezähler um 50 kWh (Zählertausch), 11:35 springt er um 30 kWh (Messfehler) | 11:00–11:15 und 11:30–11:45 leer; 11:15–11:30 und 11:45–12:00 wieder erfasst |
| UC2-11 | `/gplug.json` = `{"key_ein":"Lief_HT+Lief_NT","key_bez":"Bezug_HT+Bezug_NT","einheit":"Wh"}`, Zähler meldet diese Register in Wh | Bezug 05:00–05:15 und Einspeisung 11:00–11:15 korrekt (±2 Wh) |
| UC2-12 | Bezugszähler um 23:45 und 00:00 vergleichen, Abfrage 00:00:05 | `b[95]` (gestern 23:45–24:00) = Differenz in Wh (±2); `b[96+95]` (heute 23:45) leer |

### Abnahmetests (ausführbar)

Jeder `berry`-Block unten ist ein Abnahmetest und läuft in einem **frischen Emulator** (`bash test.sh gplug ucN`). Hilfsfunktionen `T.*`: `spec/README.md`. Die App korrigieren, nie diese Blöcke — sie ändern sich nur zusammen mit der Tabelle oben.

<details><summary>Testcode (3 Blöcke)</summary>

```berry
# UC2 — Einspeisung und Bezug pro Viertelstunde erfassen
# chart.json: e/b Index 0–95 gestern, 96–191 heute; Viertelstunde q = Minute des Tages / 15
# Der Emulator simuliert einen gPlug: {"z":{"Ei":kWh,"Eo":kWh,...}}

T.test("UC2-1 Energie einer Viertelstunde = Differenz der Zählerstände (Wh)", def ()
  T.bis(11, 0)
  var a = T.eo_wh()
  T.bis(11, 15)
  var b = T.eo_wh()
  T.bis(12, 0, 5)
  var d = T.chart()
  T.check(b - a > 0, "Simulation: keine Einspeisung zwischen 11:00 und 11:15")
  T.nahe(d['e'][96 + 44], b - a, 2, "Einspeisung 11:00–11:15 in Wh")
end)

T.test("UC2-2 Viertelstunden in der Zukunft haben keinen Wert", def ()
  var d = T.chart()
  T.eq(size(d['e']), 192, "Einspeisung nur gestern und heute (kein Morgen)")
  T.eq(d['e'][96 + 53], nil, "Einspeisung 13:15–13:30 (Zukunft)")
end)

T.test("UC2-3 Fällt der Zähler aus, entsteht kein Fehler und keine Sammel-Stunde", def ()
  T.sekunden(30)
  T.zaehler_an(false)
  T.bis(14, 0, 30)
  T.zaehler_an(true)
  T.bis(16, 0, 5)
  var d = T.chart()
  T.eq(d['e'][96 + 48], nil, "12:00–12:15 (um 12:15 kein Endstand → leer, siehe „Laufende Viertelstunde“)")
  T.eq(d['e'][96 + 55], nil, "13:45–14:00 (Zähler aus)")
  T.eq(d['e'][96 + 56], nil, "14:00–14:15 (Ausfall > 15 min: keine Differenz über mehrere Viertelstunden)")
  T.check(d['e'][96 + 60] != nil, "15:00–15:15 wieder erfasst")
end)

T.test("UC2-4 Nachts wird nichts eingespeist (Wert 0, nicht leer)", def ()
  T.bis(3, 0, 5)
  var d = T.chart()
  T.eq(d['e'][96 + 5], 0, "Einspeisung 01:15–01:30")
end)

T.test("UC2-5 Bezug einer Viertelstunde = Differenz des Bezugszählers (Wh)", def ()
  T.bis(5, 0)
  var a = T.ei_wh()
  T.bis(5, 15)
  var b = T.ei_wh()
  T.sekunden(5)
  var d = T.chart()
  T.check(b - a > 0, "Simulation: kein Bezug zwischen 05:00 und 05:15")
  T.nahe(d['b'][96 + 20], b - a, 2, "Bezug 05:00–05:15 in Wh")
end)

T.test("UC2-6 Die laufende Viertelstunde zeigt den Stand seit der letzten Ablesung (spätestens nach 1 min)", def ()
  T.bis(7, 15)
  var a = T.ei_wh()
  T.bis(7, 21)
  var b = T.ei_wh()
  T.sekunden(65)
  var d = T.chart()
  T.check(d['b'][96 + 29] != nil || d['b'][29] == nil,
    "laufende Viertelstunde steht bei gestern (Index 29) statt heute — Index heute = 96 + Viertelstunde (125)")
  T.check(d['b'][96 + 29] != nil, "laufende Viertelstunde 07:15 ohne Bezugswert")
  T.check(d['b'][96 + 29] >= b - a, "laufende Viertelstunde kleiner als der Bezug 07:15–07:21")
  T.enthaelt(T.sensor(), '"b":', "Momentanwert Bezug heute (gp_d)")
end)

T.test("UC2-7 Zähler mit Tarifregistern (Ei1/Ei2, Eo1/Eo2): die Summe zählt", def ()
  T.zaehler_tarife(true)
  T.bis(5, 0)
  var a = T.ei_wh()
  T.bis(5, 15)
  var b = T.ei_wh()
  T.bis(11, 0)
  var c = T.eo_wh()
  T.bis(11, 15)
  var e = T.eo_wh()
  T.sekunden(5)
  var d = T.chart()
  T.check(e - c > 0, "Simulation: keine Einspeisung zwischen 11:00 und 11:15")
  T.nahe(d['b'][96 + 20], b - a, 2, "Bezug 05:00–05:15 (Niedertarif, Ei2) in Wh")
  T.nahe(d['e'][96 + 44], e - c, 2, "Einspeisung 11:00–11:15 (Hochtarif, Eo1) in Wh")
end)

T.test("UC2-10 Sinkender Zählerstand (Zählertausch) und Sprung über 20000 Wh werden verworfen", def ()
  T.zaehler_tarife(false)
  T.bis(11, 5)
  T.zaehler_sprung(0, -50000)
  T.bis(11, 35)
  T.zaehler_sprung(0, 30000)
  T.bis(12, 0, 5)
  var d = T.chart()
  T.eq(d['e'][96 + 44], nil, "11:00–11:15 (Zählerstand gesunken)")
  T.eq(d['e'][96 + 46], nil, "11:30–11:45 (über 20000 Wh)")
  T.check(d['e'][96 + 45] != nil && d['e'][96 + 45] < 5000, "11:15–11:30 wieder erfasst (neue Basis)")
  T.check(d['e'][96 + 47] != nil && d['e'][96 + 47] < 5000, "11:45–12:00 wieder erfasst (neue Basis)")
end)

T.test("UC2-12 Die Viertelstunde 23:45–24:00 gehört zu gestern (Index 95), nicht zu heute", def ()
  T.bis(23, 45)
  var a = T.ei_wh()
  T.bis(0, 0)
  var b = T.ei_wh()
  T.sekunden(5)
  var d = T.chart()
  T.check(b - a > 0, "Simulation: kein Bezug zwischen 23:45 und 24:00")
  T.eq(d['b'][96 + 95], nil, "heute 23:45 (Index 191) ist Zukunft — die Viertelstunde 23:45–24:00 gehört zu gestern")
  T.nahe(d['b'][95], b - a, 2, "Bezug gestern 23:45–24:00 (Index 95) in Wh")
end)
```

```berry
# UC2 — Neustart: Tasmota-SML meldet bis zum ersten Telegramm alle Werte als 0

T.test("UC2-9 Stand 0 nach einem Neustart wird nicht zur Basis (kein Riesenwert um Mitternacht)", def ()
  T.bis(23, 59, 45)
  T.zaehler_null(true)
  T.neustart(0)
  T.sekunden(60)
  T.zaehler_null(false)
  T.bis(0, 15)
  var a = T.ei_wh()
  T.bis(0, 30)
  var b = T.ei_wh()
  T.sekunden(5)
  var d = T.chart()
  for i: 95 .. 97
    T.check(d['e'][i] == nil || d['e'][i] < 5000, f"Einspeisung Index {i} = {d['e'][i]} Wh (Stand 0 als Basis?)")
    T.check(d['b'][i] == nil || d['b'][i] < 5000, f"Bezug Index {i} = {d['b'][i]} Wh (Stand 0 als Basis?)")
  end
  T.nahe(d['b'][97], b - a, 2, "Bezug 00:15–00:30 in Wh")
end)
```


```berry
# UC2 — Zählerschlüssel und Einheit aus /gplug.json
# Namen, die die Namenssuche nicht findet, Zählerstände in Wh. Was vor dem ersten T.test steht,
# gilt schon beim Start der App.

T.schreiben("/gplug.json", '{"key_ein":"Lief_HT+Lief_NT","key_bez":"Bezug_HT+Bezug_NT","einheit":"Wh"}')
T.zaehler_tarife(true, ["Bezug_HT", "Bezug_NT", "Lief_HT", "Lief_NT"], true)

T.test("UC2-11 Zählerschlüssel (Summe) und Einheit Wh aus /gplug.json", def ()
  T.bis(5, 0)
  var a = T.ei_wh()
  T.bis(5, 15)
  var b = T.ei_wh()
  T.bis(11, 0)
  var c = T.eo_wh()
  T.bis(11, 15)
  var e = T.eo_wh()
  T.sekunden(5)
  var d = T.chart()
  T.check(e - c > 0, "Simulation: keine Einspeisung zwischen 11:00 und 11:15")
  T.nahe(d['b'][96 + 20], b - a, 2, "Bezug 05:00–05:15 (Bezug_HT+Bezug_NT, Wh) in Wh")
  T.nahe(d['e'][96 + 44], e - c, 2, "Einspeisung 11:00–11:15 (Lief_HT+Lief_NT, Wh) in Wh")
end)
```
</details>
