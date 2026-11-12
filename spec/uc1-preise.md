# UC1: Einspeisetarife der BKW abrufen

## Beschreibung

Die App holt die dynamischen Einspeisetarife der BKW und speichert jeden
der 96 Viertelstundenpreise eines Tages (gleiche Auflösung wie Zähler und Grafik). Abgerufen wird nach
dem Start und danach stündlich (Minute 5), aber nur, wenn Daten fehlen:
die Tarife für heute, oder ab 18 Uhr die Tarife für morgen.

## API

- **URL**: `https://api.bkw.ch/api/dyntariffs/v1/Tariffs/energyreturn`
- **Methode**: GET, keine Authentifizierung
- **Antwort** (~21 kB, 96 Einträge, UTC; vor ~18 Uhr heute, danach morgen):

```json
{
  "publication_timestamp": "2026-10-30T20:40:00Z",
  "prices": [
    {
      "start_timestamp": "2026-10-30T23:00:00Z",
      "end_timestamp": "2026-10-30T23:15:00Z",
      "feed_in": [ { "unit": "CHF_kWh", "value": 0.23 } ]
    }
  ]
}
```

Beispiel einer echten Antwort (nur auf dem Notebook; im Agent-Container ausgeblendet, das Format oben genügt): `emulator/fixtures/bkw_energyreturn_2026-11-05.json`.

**Jede Viertelstunde hat einen eigenen Preis.** Die App darf keine Stundenpreise annehmen.

## Daten

| Feld | Typ | Grösse |
|---|---|---|
| Viertelstundentarif, 3 Tage (gestern, heute, morgen) × 96 | int16 in 0.01 Rp/kWh, Marker 0x8000 = leer | 576 B |
| Speicher für Neustart | `/gplug_preise.json` | ~1.2 kB Flash |

## Randbedingungen

- **Die Antwort nie ganz in den Speicher laden** (kein `json.load()`, kein `get_string()`): dafür reicht der Heap des ESP32-C3 nicht — `json.load` startet das Gerät neu, `get_string` schneidet ohne Fehlermeldung ab. Die Antwort in eine Datei streamen, stückweise lesen, danach löschen (Skill `tasmota-berry`, „Einträge mit mehreren Feldern stückweise lesen“).
- Jeder Preis gehört in seine **lokale** Viertelstunde (die API liefert UTC; Winter +1 h, Sommer +2 h). „Tag“ = Tage seit 1970 (z.B. 20768 für den 11.11.2026), nicht der Tag im Monat.
- Weniger als 96 Viertelstunden = unvollständig → als Fehler zählen.
- Fehler (HTTP ≠ 200, keine oder zu wenige Preise) → Log-Eintrag, alte Werte bleiben, nächster Versuch zur nächsten Minute 5.
- **Start vor der Zeitsynchronisation:** Tasmota lädt die App vor NTP. Der erste Abruf erfolgt, sobald die Uhr gültig ist — das wiederholt prüfen, nicht nur einmal (UC1-9). Alles Tagesbezogene (Puffer auf „heute“ schieben) ebenfalls erst mit gültiger Uhr, sonst gehen die gespeicherten Tarife verloren (UC1-10).
- `_emu_…` und `T.…` in den Tests sind Werkzeuge des Emulators; auf dem gPlug gibt es sie nicht (`build.sh` lehnt sie ab).

## Schnittstelle, über die die Tests prüfen

Die Tests lesen die Preise aus **`GET /gplug/chart.json`** (Vertrag vollständig in `spec/uc3-webui.md`).
Für UC1 genügt:

```json
{"t": 1793318400, "n": 1793354400, "p": "<Base64>"}
```

- `t` = gestern 00:00, `n` = jetzt (lokale Epoch-Sekunden)
- `p` = **Base64-Text** des 576-Byte-Puffers, **keine JSON-Liste**: 288 Werte int16 little-endian,
  `0x8000` = leer; Index 0–95 gestern, 96–191 heute, 192–287 morgen.
- `e`/`b` (Energie, UC2) dürfen fehlen, bis UC2 umgesetzt ist.

Falsches Format → der Test meldet `chart.json (spec/uc3-webui.md): …`.

## Tests

| ID | Test | Erwartung |
|---|---|---|
| UC1-1 | Start um 10:00, eine Minute warten | mindestens ein Abruf; `chart.json` hat 96 Preise für heute (Index 96–191) |
| UC1-2 | alle 96 Viertelstundenpreise von heute mit der Fixture vergleichen (Preise ändern innerhalb der Stunde) | Preis × 10 000, gerundet (±1) |
| UC1-3 | bis 17:59 laufen lassen | keine weiteren Abrufe |
| UC1-4 | bis 18:10, dann bis 23:59 | genau ein weiterer Abruf; 96 Preise für morgen (`p`, Index 192–287) |
| UC1-5 | bis 00:30 am Folgetag | gestern und heute haben je 96 Preise |
| UC1-6 | Dateisystem prüfen | Tarife sind in einer Datei gesichert |
| UC1-7 | API liefert Netzwerkfehler | kein Absturz; `chart.json` und Sensorzeilen funktionieren (Hauptseite: UC3-6) |
| UC1-8 | Fehler, dann API wieder erreichbar | neuer Versuch innerhalb einer Stunde; danach 96 Preise für heute |
| UC1-9 | Neustart, die Uhr ist erst nach 60 s gültig (vor NTP) | spätestens 2 min danach ein Abruf; 96 Preise für heute |
| UC1-10 | Neustart vor NTP, API nicht erreichbar | die gespeicherten 96 Preise für heute sind nach dem Start noch da (nicht gelöscht) |
| UC1-11 | danach bis 00:30, API weiter nicht erreichbar | gestern 96 Preise (verschoben), heute und morgen leer |

### Abnahmetests (ausführbar)

Jeder `berry`-Block unten ist ein Abnahmetest und läuft in einem **frischen Emulator** (`bash test.sh gplug ucN`). Hilfsfunktionen `T.*`: `spec/README.md`. Die App korrigieren, nie diese Blöcke — sie ändern sich nur zusammen mit der Tabelle oben.

<details><summary>Testcode (3 Blöcke)</summary>

```berry
# UC1 — Einspeisetarife der BKW abrufen
# Start: Mi 11.11.2026 10:00. Die Fixture liefert vor 18 Uhr den heutigen,
# ab 18 Uhr den morgigen Tag (wie die echte API).

import json

def T_iso(s)
  return _emu_days_from_civil(int(s[0..3]), int(s[5..6]), int(s[8..9])) * 86400 + int(s[11..12]) * 3600 + int(s[14..15]) * 60
end

# Erwarteter Viertelstundenpreis in 0.01 Rp/kWh direkt aus der Fixture
def erwartet(tag, q)
  var d = json.load(_emu_bkw_fixture(tag, 0))
  var tz = _emu_tz_offset(tag * 86400) * 60
  for e: d['prices']
    var loc = T_iso(e['start_timestamp']) + tz
    if loc / 900 == tag * 96 + q
      var v = e['feed_in'][0]['value'] * 10000
      return int(v >= 0 ? v + 0.5 : v - 0.5)
    end
  end
  return nil
end

def zaehle(liste, von, bis)
  var n = 0
  for i: von .. bis if liste[i] != nil n += 1 end end
  return n
end

T.test("UC1-1 Innerhalb einer Minute nach dem Start werden die Tarife von heute abgerufen", def ()
  T.sekunden(60)
  T.check(T.abrufe() >= 1, "kein Aufruf der BKW-API")
  var d = T.chart()
  T.eq(zaehle(d['p'], 96, 191), 96, "Anzahl Viertelstundenpreise für heute (Index 96–191)")
end)

T.test("UC1-2 Preis jeder Viertelstunde in 0.01 Rp/kWh (ändert innerhalb der Stunde)", def ()
  var d = T.chart()
  for q: 0 .. 95
    T.nahe(d['p'][96 + q], erwartet(T.heute(), q), 1, "Preis Viertelstunde " + str(q))
  end
end)

T.test("UC1-3 Vor 18 Uhr kein weiterer Abruf, wenn heute vollständig ist", def ()
  var n = T.abrufe()
  T.bis(17, 59)
  T.eq(T.abrufe(), n, "Anzahl Abrufe bis 17:59")
end)

T.test("UC1-4 Ab 18 Uhr werden die Tarife für morgen geholt — genau einmal", def ()
  var n = T.abrufe()
  T.bis(18, 10)
  T.eq(T.abrufe(), n + 1, "Abrufe bis 18:10")
  var d = T.chart()
  T.eq(zaehle(d['p'], 192, 287), 96, "Viertelstundenpreise für morgen (Index 192–287)")
  T.nahe(d['p'][192 + 33], erwartet(T.heute() + 1, 33), 1, "Preis morgen 08:15 Uhr")
  T.bis(23, 59)
  T.eq(T.abrufe(), n + 1, "keine weiteren Abrufe bis 23:59")
end)

T.test("UC1-5 Nach Mitternacht sind die Tarife von gestern und heute noch da", def ()
  T.bis(0, 30)
  var d = T.chart()
  T.eq(zaehle(d['p'], 0, 95), 96, "Viertelstundenpreise gestern")
  T.eq(zaehle(d['p'], 96, 191), 96, "Viertelstundenpreise heute")
end)

T.test("UC1-6 Tarife werden für einen Neustart im Dateisystem gesichert", def ()
  var gefunden = false
  for f: T.dateien()
    if f != "_persist.json" && size(f) > 0 gefunden = true end
  end
  T.check(gefunden, "keine Datei im Dateisystem geschrieben")
end)
```

```berry
# UC1 — Verhalten bei Netzwerkfehlern

T.netz("error")

T.test("UC1-7 API nicht erreichbar: kein Absturz, chart.json und Sensorzeilen bleiben bedienbar", def ()
  T.sekunden(60)
  T.check(T.abrufe() >= 1, "kein Abrufversuch")
  T.eq(T.http("/gplug/chart.json")['code'], 200, "chart.json bei fehlenden Preisen")
  T.check(size(T.sensor()) > 0, "keine Sensorzeilen")
end)

T.test("UC1-8 Nach einem Fehler wird spätestens nach einer Stunde erneut versucht", def ()
  var n = T.abrufe()
  T.stunden(1)
  T.check(T.abrufe() > n, "kein neuer Versuch innerhalb einer Stunde")
  T.netz("fixture")
  T.stunden(1)
  var d = T.chart()
  var k = 0
  for i: 96 .. 191 if d['p'][i] != nil k += 1 end end
  T.eq(k, 96, "Viertelstundenpreise für heute nach Wiederherstellung")
end)
```

```berry
# UC1 — Start vor der Zeitsynchronisation (NTP)
# T.neustart(60): App neu laden wie beim Booten, Dateisystem bleibt; die ersten 60 s liefert
# tasmota.rtc() nur die Sekunden seit dem Start (~0), wie auf dem Gerät vor NTP.

def zaehle(liste, von, bis)
  var n = 0
  for i: von .. bis if liste[i] != nil n += 1 end end
  return n
end

def heute_96()
  return zaehle(T.chart()['p'], 96, 191)
end

T.test("UC1-9 Start vor NTP: abgerufen wird, sobald die Uhr stimmt (nicht erst zur nächsten Stunde)", def ()
  T.neustart(60)
  T.sekunden(180)
  T.check(T.abrufe() >= 1, "kein Abruf in den ersten 2 min nach gültiger Uhr — den Start wiederholt prüfen (Timer), nicht nur einmal")
  T.eq(heute_96(), 96, "Viertelstundenpreise für heute nach dem Start vor NTP")
end)

T.test("UC1-10 Neustart vor NTP löscht die gespeicherten Tarife nicht", def ()
  T.netz("error")
  T.neustart(60)
  T.sekunden(180)
  T.eq(heute_96(), 96, "Tarife von heute nach dem Neustart (aus der Datei; die API ist nicht erreichbar) — Puffer erst mit gültiger Uhr auf heute schieben")
end)

T.test("UC1-11 Nach Mitternacht ohne API: die Tarife von heute werden zu gestern, heute bleibt leer", def ()
  T.bis(0, 30)
  var d = T.chart()
  T.eq(zaehle(d['p'], 0, 95), 96, "gestern (Index 0–95): die gespeicherten Tarife, um einen Tag verschoben")
  T.eq(zaehle(d['p'], 96, 191), 0, "heute (Index 96–191): leer, die API ist nicht erreichbar")
  T.eq(zaehle(d['p'], 192, 287), 0, "morgen (Index 192–287): leer")
end)
```

</details>
