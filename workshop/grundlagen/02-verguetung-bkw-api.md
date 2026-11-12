# 2 · Dynamische Vergütung und die BKW-API

## Warum „Vergütung 2027“?

<!-- TODO Leitung: Rechtsgrundlage und BKW-Produkt für 2027 kurz ergänzen/prüfen -->
Bisher bekommen PV-Besitzer meist einen fixen Rücklieferpreis pro kWh. Die BKW
veröffentlicht **dynamische Einspeisetarife**: Der Preis folgt dem Strommarkt —
in Viertelstunden, Tag für Tag anders. Mittags, wenn alle PV-Anlagen liefern,
ist er tief; am Abend hoch (siehe Grafik der Referenzlösung).

Wer wissen will, was die eigene Anlage wirklich einbringt, muss deshalb **jede
Viertelstunde** Energie × Tarif rechnen — genau das macht unsere App.

## Die API

```
GET https://api.bkw.ch/api/dyntariffs/v1/Tariffs/energyreturn
```

Keine Anmeldung, Antwort ~21 kB JSON:

```json
{
  "publication_timestamp": "2026-10-30T20:40:00Z",
  "prices": [
    {
      "start_timestamp": "2026-10-30T23:00:00Z",
      "end_timestamp": "2026-10-30T23:15:00Z",
      "feed_in": [ { "unit": "CHF_kWh", "value": 0.23 } ]
    },
    …  96 Einträge
  ]
}
```

- **96 Viertelstunden** eines Tages, Zeitstempel in **UTC**. Seit 05.11.2026 hat jede
  Viertelstunde einen eigenen Preis (vorher galt ein Preis für die ganze Stunde).
  (`23:00Z` = 00:00 Uhr in der Schweiz im Winter, 01:00 im Sommer).
- Vor ~18 Uhr kommt **heute**, danach **morgen**.
- Preis in **CHF/kWh**; wir speichern Rp/kWh × 100 als Ganzzahl (0.223 CHF → 2230).

Ausprobieren: `curl -s https://api.bkw.ch/api/dyntariffs/v1/Tariffs/energyreturn | head -30`
Gespeicherte echte Antwort: `emulator/fixtures/bkw_energyreturn_2026-11-05.json`.

## Die wichtigste Lektion: 21 kB sind auf dem gPlug viel

Auf einem gPlugK gemessen (Tasmota 15.3.0, dazu lief schon `gplug_ha.tapp`):

| Variante | freier Heap | Ergebnis |
|---|---|---|
| nur Tasmota + `gplug_ha` | ~114 kB | — |
| `get_string()` + `json.load()` | — | **Neustart** |
| unsere App + `get_string()` + Text-Suche | ~68 kB, 45 % fragmentiert | **nur 39 von 96** Viertelstunden — ohne Fehlermeldung |
| unsere App + `write_file()` + 1-kB-Stücke | **~90 kB** | 96 von 96 |

Warum? `json.load` baut für jede Viertelstunde Maps, Listen und Strings — ein
Vielfaches der 21 kB. Und `get_string()` braucht **einen zusammenhängenden**
21-kB-Block; ob es den gibt, hängt davon ab, was sonst auf dem Gerät läuft. Am
eigenen Schreibtisch klappt es, beim Kunden nicht.

Darum: Antwort direkt ins Dateisystem streamen, dann stückweise lesen.

```berry
var cl = webclient()
cl.begin(url)
var code = cl.GET()
var n = code == 200 ? cl.write_file("/gplug_bkw.tmp") : 0
cl.close()
var f = open("/gplug_bkw.tmp", "r")
var rest = ""
while true
  var teil = f.read(1024)
  var s = rest + teil
  # … '"start_timestamp"' und '"value"' in s suchen, vollständige Einträge auswerten …
  rest = …               # angefangener Eintrag am Ende → ins nächste Stück
  if size(teil) == 0 break end
end
```

Ganze Umsetzung: `referenz/gplug/uc1_preise.be`. Der Emulator warnt, wenn eine
App `get_string()` mit mehr als 8 kB benutzt.

## Rechnen

| Grösse | Formel |
|---|---|
| Tarif der Viertelstunde | BKW-Preis, wie geliefert |
| Energie der Viertelstunde | Zählerstand `Eo` um :00/:15/:30/:45 − Zählerstand 15 min vorher |
| Vergütung der Viertelstunde | Energie (kWh) × Tarif (CHF/kWh) |
| Bezug | nur als Energie (kWh) — **Einspeisetarif ≠ Bezugstarif**, den Bezugstarif liefert die API nicht |

Feiner als 15 min lohnt sich nicht: die Grafik zeigt 3 Tage auf 288 SVG-Einheiten —
eine Viertelstunde pro Einheit, auf die Breite der Box skaliert.
