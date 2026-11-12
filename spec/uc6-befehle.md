# UC6: Tasmota-Befehle (Zusatz, zuletzt)

## Beschreibung

Nur umsetzen, wenn Zeit bleibt. **Kein anderer Use Case braucht diese Befehle** — UC1 bis UC5
laufen und testen ohne sie.

Drei Befehle für Konsole, HTTP (`http://<gplug>/cm?cmnd=GplugInfo`) und MQTT.
Gross-/Kleinschreibung egal. Antworten sind JSON mit dem Befehlsnamen als Schlüssel.

| Befehl | Antwort |
|---|---|
| `GplugInfo` | `{"GplugInfo":{"Version","Zeit","Preise_heute","Preise_morgen","Letzter_Abruf","Abruf_Fehler","Viertelstunden_heute","Zaehler_Eo_Wh","Zaehler_Ei_Wh","Zaehler","Heap_kB"}}` — `Preise_*`, `Viertelstunden_heute`: Anzahl Viertelstunden mit Wert (max. 96); `Zaehler`: verwendete Zählerschlüssel, z.B. `"Eo kWh / Ei kWh"` (mit UC5 auch die Quelle: `"script.txt: Lief_HT+Lief_NT Wh / …"`) |
| `GplugPreise` | `{"GplugPreise":{"ab":"2026-11-11T10:00:00","rp_kwh":[12 Werte oder null]}}` — Tarife der nächsten 12 Viertelstunden (3 h) ab der laufenden |
| `GplugAbruf` | ruft die BKW-API sofort ab → `{"GplugAbruf":"Done"}` oder `"Fail"` |

## Tests

| ID | Test | Erwartung |
|---|---|---|
| UC6-1 | `GplugInfo` nach dem Start | JSON mit `GplugInfo.Preise_heute` = 96 |
| UC6-2 | `gplugpreise` (klein geschrieben) um 10:01 | `ab` = `2026-11-11T10:00:00` (Anfang der laufenden Viertelstunde); 12 Werte; der erste zwischen 0 und 100 Rp/kWh |
| UC6-3 | `GplugAbruf` | genau ein Abruf mehr; Antwort `Done` |
| UC6-4 | `GplugAbruf`, API nicht erreichbar | Antwort `Fail`, kein Absturz |
| UC6-5 | `GplugInfo` mit dem Standardzähler (`Eo`/`Ei`) | `Zaehler` nennt `Eo` und `Ei`; `Zaehler_Eo_Wh`, `Zaehler_Ei_Wh` = Zählerstände in Wh (±2) |

### Abnahmetests (ausführbar)

Jeder `berry`-Block unten ist ein Abnahmetest und läuft in einem **frischen Emulator** (`bash test.sh gplug ucN`). Hilfsfunktionen `T.*`: `spec/README.md`. Die App korrigieren, nie diese Blöcke — sie ändern sich nur zusammen mit der Tabelle oben.

<details><summary>Testcode (1 Block)</summary>

```berry
# UC6 — Tasmota-Befehle

T.test("UC6-1 GplugInfo liefert den Zustand als JSON", def ()
  T.sekunden(60)
  var r = T.cmd("GplugInfo")
  T.check(isinstance(r, map) && r.contains("GplugInfo"), "Antwort ohne GplugInfo: " + str(r))
  T.eq(r["GplugInfo"]["Preise_heute"], 96, "Preise_heute (Viertelstunden)")
end)

T.test("UC6-2 GplugPreise liefert die Tarife der nächsten 12 Viertelstunden", def ()
  var r = T.cmd("gplugpreise")
  T.check(isinstance(r, map) && r.contains("GplugPreise"), "Antwort ohne GplugPreise: " + str(r))
  var l = r["GplugPreise"]["rp_kwh"]
  T.eq(r["GplugPreise"]["ab"], "2026-11-11T10:00:00", "ab = Anfang der laufenden Viertelstunde")
  T.eq(size(l), 12, "Anzahl Werte")
  T.check(l[0] != nil && l[0] > 0 && l[0] < 100, "Tarif jetzt in Rp/kWh plausibel: " + str(l[0]))
end)

T.test("UC6-3 GplugAbruf holt die Tarife sofort", def ()
  var n = T.abrufe()
  var r = T.cmd("GplugAbruf")
  T.eq(T.abrufe(), n + 1, "Anzahl Abrufe")
  T.eq(r["GplugAbruf"], "Done", "Antwort")
end)

T.test("UC6-4 GplugAbruf ohne Netz antwortet Fail", def ()
  T.netz("error")
  var r = T.cmd("GplugAbruf")
  T.eq(r["GplugAbruf"], "Fail", "Antwort bei Netzwerkfehler")
end)

T.test("UC6-5 GplugInfo nennt Zählerschlüssel und Zählerstände", def ()
  T.sekunden(60)
  var info = T.cmd("GplugInfo")["GplugInfo"]
  T.enthaelt(info["Zaehler"], "Eo", "Zaehler: Einspeiseschlüssel")
  T.enthaelt(info["Zaehler"], "Ei", "Zaehler: Bezugsschlüssel")
  T.nahe(info["Zaehler_Eo_Wh"], T.eo_wh(), 2, "Zaehler_Eo_Wh")
  T.nahe(info["Zaehler_Ei_Wh"], T.ei_wh(), 2, "Zaehler_Ei_Wh")
end)
```

</details>
