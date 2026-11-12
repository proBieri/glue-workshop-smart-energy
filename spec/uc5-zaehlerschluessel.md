# UC5: Zählerschlüssel automatisch aus dem SML-Skript (Zusatz)

## Beschreibung

In UC2 trägt man abweichende Zählernamen von Hand in `/gplug.json` ein. UC5 erkennt sie
automatisch aus dem SML-Skript, das den Zähler auf dem gPlug ausliest. Die Reihenfolge
(20 s nach dem Start) wird damit:

1. **`/gplug.json`** wie in UC2 — hat Vorrang, aber **nur wenn die Datei Schlüssel enthält**.
   Eine Datei nur mit `csv_monate` zählt nicht: fehlende Schlüssel nicht mit `Eo`/`Ei` füllen,
   sonst kommt Schritt 2 nie zum Zug (UC5-1).
2. **SML-Skript `/script.txt`** (das aktive Tasmota-Scripter-Skript), Abschnitt `>M` — neu in UC5.
3. **Namenssuche** wie in UC2.

Hat die App die Befehle aus UC6 (Zusatz), zeigt `GplugInfo` das Ergebnis im Feld `Zaehler`,
z.B. `"script.txt: Lief_HT+Lief_NT Wh / Bezug_HT+Bezug_NT Wh"` — für UC5 nicht nötig.

## SML-Skript

Jede Zeile im Abschnitt `>M` beschreibt einen Wert, z.B.:

```
1,1-0:2.8.1(@1,Eo1 ___ 2⋅8⋅1,kWh,Eo1,3
```

| Teil | Bedeutung |
|---|---|
| `1-0:C.D.E` (oder SML binär `77070100CCDDEEff`) | OBIS-Code; Energiezähler haben `D = 8` |
| `C` | `1` Bezug, `2` Einspeisung |
| `E` | `0` Gesamtstand, `1, 2 …` Tarifregister — gibt es `E = 0`, zählt nur der, sonst die Summe der Register |
| nach `(@` | 1 Teiler, 2 Text (darf Leerzeichen enthalten), **3 Einheit** (`kWh` oder `Wh`), **4 JSON-Name**, 5 Stellen |

Der Teiler ist in `Status 10` schon angewendet — die App braucht nur Name und Einheit.
Zeilen mit `;` sind Kommentare.

## Tests

| ID | Test | Erwartung |
|---|---|---|
| UC5-1 | `/script.txt` nennt `Bezug_HT`/`_NT`, `Lief_HT`/`_NT` in **Wh**; `/gplug.json` enthält nur `csv_monate`; der Zähler meldet diese Register in Wh | Bezug 05:00–05:15 und Einspeisung 11:00–11:15 korrekt in Wh (±2) |
| UC5-2 | `/gplug.json` mit `key_ein`/`key_bez` = `Eo`/`Ei`, `/script.txt` nennt Namen, die der Zähler nicht liefert | die Konfiguration hat Vorrang: Einspeisung 11:00–11:15 korrekt (±2 Wh) |

### Abnahmetests (ausführbar)

Jeder `berry`-Block unten ist ein Abnahmetest und läuft in einem **frischen Emulator** (`bash test.sh gplug uc5`). Hilfsfunktionen `T.*`: `spec/README.md`. Die App korrigieren, nie diese Blöcke — sie ändern sich nur zusammen mit der Tabelle oben.

<details><summary>Testcode (2 Blöcke)</summary>

```berry
# UC5 — Zählernamen und Einheit aus dem SML-Skript (/script.txt)
# Namen, die die Namenssuche nicht findet, Zählerstände in Wh statt kWh.
# Was vor dem ersten T.test steht, gilt schon beim Start der App.

T.schreiben("/script.txt", ">D 25\n; gPlug Test\n; Kommentar: 1-0:2.8.0 ist hier kein Zähler\n>B\n->sensor53 r\n\n>M 1\n+1,4,o,0,115200,z\n\n1,0-0:96.1.1(@#),*,,SMid,0\n1,=h<hr/>\n1,1-0:1.7.0(@1,Pi ___ 1⋅7,kW,Pi,3\n1,1-0:21.7.0(@0.001,P1i ___ 21⋅7,W,P1i,0\n;1,1-0:2.8.0(@1,Eo,kWh,Eo,3\n1,1-0:1.8.1(@0.001,Bezug HT,Wh,Bezug_HT,0\n1,1-0:1.8.2(@0.001,Bezug NT,Wh,Bezug_NT,0\n1,1-0:2.8.1(@0.001,Lieferung HT,Wh,Lief_HT,0\n1,1-0:2.8.2(@0.001,Lieferung NT,Wh,Lief_NT,0\n#\n\n>S\nupH=uptime/60\n")
T.schreiben("/gplug.json", '{"csv_monate":3}')
T.zaehler_tarife(true, ["Bezug_HT", "Bezug_NT", "Lief_HT", "Lief_NT"], true)

T.test("UC5-1 Zählernamen und Einheit (Wh) aus /script.txt ergeben die richtigen Wh", def ()
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
  T.nahe(d['b'][96 + 20], b - a, 2, "Bezug 05:00–05:15 (Bezug_NT, Wh) in Wh")
  T.nahe(d['e'][96 + 44], e - c, 2, "Einspeisung 11:00–11:15 (Lief_HT, Wh) in Wh")
end)
```

```berry
# UC5 — /gplug.json hat Vorrang vor dem SML-Skript
# Das Skript nennt Namen, die der Zähler nicht liefert; nur mit der Konfiguration stimmt es.

T.schreiben("/script.txt", ">D 25\n>M 1\n+1,4,o,0,115200,z\n1,1-0:1.8.0(@1,Bezug,kWh,Bezug_X,3\n1,1-0:2.8.0(@1,Lieferung,kWh,Lief_X,3\n#\n")
T.schreiben("/gplug.json", '{"key_ein":"Eo","key_bez":"Ei"}')

T.test("UC5-2 Zählerschlüssel aus /gplug.json haben Vorrang vor /script.txt", def ()
  T.bis(11, 0)
  var a = T.eo_wh()
  T.bis(11, 15)
  var b = T.eo_wh()
  T.sekunden(5)
  var d = T.chart()
  T.check(b - a > 0, "Simulation: keine Einspeisung zwischen 11:00 und 11:15")
  T.nahe(d['e'][96 + 44], b - a, 2, "Einspeisung 11:00–11:15 in Wh (Schlüssel Eo aus /gplug.json)")
end)
```

</details>
