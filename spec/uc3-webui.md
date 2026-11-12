# UC3: 3-Tage-Grafik im WebUI (Viertelstunden)

## Beschreibung

Auf der Tasmota-Hauptseite erscheint oberhalb von Tasmotas Sensortabelle ein Widget mit
Kacheln (Momentanwerte) und einer Grafik über gestern, heute und morgen. **Das Widget ist
vorgegeben** (`gplug/gplug_ui.html`, siehe unten); die App liefert nur die Daten.

<details><summary>Was das Widget zeigt (Gestaltung, nur von Auge prüfbar)</summary>


1. **Kacheln mit Momentanwerten** (gross, gut lesbar, alle ~2 s aktuell):
   Einspeisetarif jetzt (Rp/kWh, rot wenn negativ), Vergütung heute (CHF),
   Einspeisung heute (kWh), Bezug heute (kWh).
2. **Grafik: gestern, heute und morgen** in Viertelstunden, **1 SVG-Einheit pro
   Viertelstunde** (3 × 96 = 288 Einheiten Zeichenfläche); das SVG füllt die Breite
   der Box (`width:100%`):
   - Energie pro Viertelstunde mit gemeinsamer Null-Linie: **Einspeisung nach oben** (grün; braun,
     wenn der Preis negativ ist), **Bezug nach unten** (violett), beides in kWh pro Viertelstunde
   - Spotpreis (Einspeisetarif) als Linie mit eigener Skala; negativer Bereich schattiert
   - **Jede Achse nennt ihre Einheit** (über der Achse): links `kWh/¼h`, rechts `Rp/kWh`,
     unten Vergütung `CHF/¼h`. Jeder Achsenwert steht **auf der Höhe seiner Linie** (der
     oberste Wert nicht unter die Einheit schieben).
   - Achsen mit Uhrzeit (00/12) und Datum („Do 11.06.“), Markierung „jetzt“ (genaue Uhrzeit,
     nicht auf die Viertelstunde gerundet). Jeder Tag ist gleich breit (96 Viertelstunden,
     00:00–24:00 Lokalzeit; die BKW liefert UTC, die App ordnet jeden Preis seiner lokalen
     Viertelstunde zu)
   - **Werte unter der Maus**: fährt die Maus über die Grafik
     (oder tippt der Finger darauf), liegt über der Viertelstunde eine halbtransparente Spalte
     (weiss, 20 %, mind. 2 Einheiten breit, über beide Grafiken), und statt der Legende stehen
     Tag und Uhrzeit dieser Viertelstunde mit ihren Werten in den Farben der Kurven: Tarif
     (Rp/kWh), ▲ Einspeisung und ▼ Bezug (kWh), Vergütung (CHF). Leere Werte fehlen bzw. „–“;
     morgen hat nur den Tarif. Maus weg → Legende wieder da. Rein im Browser aus den schon
     geladenen `chart.json`-Daten — keine zusätzliche Anfrage, kein Berry-Code. Nur von Auge
     prüfbar.
   - darunter **Vergütung pro Viertelstunde** (CHF/¼h; orange, rot wenn die Einspeisung bei
     negativem Preis kostet) und **Σ CHF** der gezeigten Tage
   - **Morgen** als dritter, hinterlegter Abschnitt: nur der BKW-Tarif (gestrichelt), sobald
     veröffentlicht (~18 Uhr). Keine Energie- oder Vergütungsbalken (die wären immer 0).
     **Ohne Preise für morgen wird der Abschnitt ausgeblendet:** gestern und heute füllen
     die ganze Breite (1.5 Einheiten pro Viertelstunde), unten rechts steht der Hinweis
     „Tarif morgen ab ~18 Uhr“. Das entscheidet der Browser aus `p` (Index 192–287 leer);
     `chart.json` bleibt gleich. Nur von Auge prüfbar (der Emulator führt kein JavaScript aus).

</details>

### Vorgegeben: `gplug/gplug_ui.html` — nicht ändern

Alles, was oben unter 1. und 2. steht (Kacheln, Grafik, Achsen, Tooltip, Abschnitt „morgen“),
setzt die **vorgegebene Datei `gplug/gplug_ui.html`** um (HTML, CSS, JavaScript, ~8 kB). Sie
liegt schon im Starter und kommt mit `build.sh` in die `.tapp`. **Nicht ändern, kein eigenes
HTML/JavaScript schreiben — und schon gar nicht als Berry-Strings** (`js += "…"` kostet
dauerhaft Heap und vermischt die Sprachen — typische Folge: `json.load` im JavaScript, leere
Kacheln, obwohl alle Tests grün sind).

Aufgabe der App in UC3 — nur der Berry-Teil:

1. `web_add_main_button()`: die Datei aus der `.tapp` in Stücken senden (nie ganz in den Speicher).
2. `web_add_handler()`: Route `/gplug/chart.json` (Vertrag unten).
3. `web_sensor()`: das Daten-`div` `gp_d` (Vertrag unten).

Die Datei erwartet genau diese beiden Schnittstellen und erledigt den Rest im Browser.

**Vertrag der Oberfläche** (was `gplug_ui.html` vom Server erwartet und selbst tut):

| Teil | Vertrag |
|---|---|
| Einbettung | wird unverändert als Teil der Hauptseite gesendet; verschiebt ihr Widget `#gp_w` selbst mit `insertBefore` vor `#l1` (UC3-5) |
| Grafikdaten | `fetch('gplug/chart.json')` beim Laden und alle 5 min; liest `t`, `n`, `p`, `e`, `b` (Base64, int16 LE, `0x8000` = leer) |
| Momentanwerte | beobachtet `#l1` (MutationObserver), liest `#gp_d` → `data-v` als JSON `{p, e, b, v}` und füllt die Kacheln `#gk_p` (Rp/kWh), `#gk_v` (CHF), `#gk_e`, `#gk_b` (kWh) |
| Fehlende Werte | `p` = `null` → Kachel „–“; leere Viertelstunden → kein Balken, Lücke in der Preislinie |
| Grafik | SVG `#gp_g`, Legende/Tooltip `#gp_lg`, Summe `#gp_s`; alles im Browser gerechnet |

Ein Server, der `chart.json` und `gp_d` nach diesem Vertrag liefert, braucht von der Datei nichts
weiter zu wissen.

**Keine Kosten für den Bezug:** Einspeisetarif ≠ Bezugstarif, und den Bezugstarif
kennen wir nicht. Der Bezug erscheint darum nur als Energie (kWh), nirgends in CHF.

Die Skala der Vergütung reicht mindestens bis +0.01 CHF/¼h, damit Kleinstwerte nicht
als volle Balken erscheinen.

Eine SVG-Einheit ist kein festes Bildschirmpixel: das SVG wird auf die Breite der
Box skaliert, auf einem Bildschirm mit 150 % Skalierung z.B. werden aus 96 Einheiten
pro Tag ~150 Bildschirmpixel. Die Balken werden darum ohne `crispEdges` gezeichnet
(sonst rundet der Browser sie abwechselnd auf 1 und 2 Pixel). Eine feinere Erfassung
(z.B. minütlich) brächte trotzdem nichts — die Grafik bleibt bewusst einfach:
3 Tage, eine Einheit pro Viertelstunde, kein Scrollen. Bei der
Zeitumstellung hat ein Tag trotzdem 96 Plätze: im Frühling bleibt eine Stunde
leer, im Herbst wird eine überschrieben — nachts, darum in Kauf genommen.

## Schnittstellen (Vertrag)

**`GET /gplug/chart.json`** — `Content-Type: application/json`, < 2 kB:

```json
{"t": 1793318400, "n": 1793398067, "p": "FggKCO4H…", "e": "AAAAAPAF…", "b": "NgEAAU4B…"}
```

| Feld | Bedeutung |
|---|---|
| `t` | Start = **gestern 00:00**, lokale Epoch-Sekunden |
| `n` | jetzt, lokale Epoch-Sekunden |
| `p` | 288 Tarife in 0.01 Rp/kWh — Index 0–95 gestern, 96–191 heute, 192–287 morgen (ab ~18 Uhr) |
| `e` | 192 Einspeisungen in Wh — Index 0–95 gestern, 96–191 heute |
| `b` | 192 Bezugswerte in Wh, wie `e` |

Index = Tag × 96 + Viertelstunde (Sekunde des lokalen Tages / 900). `p`, `e`, `b` sind
**Base64** von je 2 Byte pro Wert: int16 little-endian, `0x8000` = leer (Skill §5).
So kopiert der Server nur die `bytes()`-Puffer — eine JSON-Liste mit 672 Zahlen
würde ~3.5 kB und eine grosse Berry-Liste im Heap kosten. Der Browser dekodiert
(`atob`, zwei Byte → Zahl).

Die laufende Viertelstunde enthält in `e`/`b` den Stand seit der letzten Ablesung.

**Hauptseite** (`web_add_main_button()`): sendet die vorgegebene `gplug_ui.html` (~8.2 kB, < 10 kB; pro Seitenaufruf einmal in Stücken gelesen, kostet nur kurz Heap).

**Momentanwerte** (`web_sensor()`, bei jedem Tasmota-Poll): nur ein unsichtbares Daten-`div`, < 400 Byte, kein SVG/Skript:

```html
<div id='gp_d' style='display:none' data-v='{"p":2300,"e":3790,"b":4154,"v":0.476}'></div>
```

| Feld | Bedeutung |
|---|---|
| `p` | Tarif der laufenden Viertelstunde in 0.01 Rp/kWh oder `null` |
| `e`, `b` | Einspeisung und Bezug heute in Wh (inkl. laufender Viertelstunde) |
| `v` | Vergütung heute in CHF |

Das Skript liest das `div` per MutationObserver auf `#l1` und füllt die Kacheln (Skill §3).

## Randbedingungen (Skill `tasmota-lowmem-webui`)

- `web_sensor()` läuft bei jeder Aktualisierung (~2 s) und ersetzt den Inhalt von `#l1` → dort nur kleine Werte.
- Statisches HTML/SVG/JS einmal pro Seitenaufruf aus `web_add_main_button()` — das ist die vorgegebene `gplug_ui.html`; sie verschiebt das Widget selbst vor `#l1`.
- Grafikdaten separat und selten holen (alle 5 min); Momentanwerte im Tasmota-Poll mitliefern (§3) statt einer zweiten Anfrage.
- Der Server sendet Rohwerte (int), der Browser rechnet Vergütung, Skalen und Summen.
- Grosse statische Texte nicht als Berry-String-Literale (permanenter Heap) — darum liegt das HTML als Datei in der `.tapp`.

## Tests

| ID | Test | Erwartung |
|---|---|---|
| UC3-1 | Hauptseite | ist die vorgegebene `gplug_ui.html` (beginnt mit `<!-- gplug_ui.html`), enthält `<svg` und `gplug/chart.json`, < 10000 Byte |
| UC3-2 | Momentanwerte | Daten-`div` `gp_d`, < 400 Byte, kein `<svg`/`<script`; `p` = Tarif der laufenden Viertelstunde, `e`/`b` = Summe heute aus `chart.json`, `v` vorhanden, **kein** `k` (keine Kostenangabe) |
| UC3-3 | `chart.json` | Content-Type JSON; `p` ist Base64-Text; `t` = gestern 00:00; `n` = jetzt; `p` 288, `e`/`b` je 192 Werte; **kein** `k`/`m`; < 2000 Byte |
| UC3-4 | nach zwei Tagen um 14:00 | gestern (Index 0–95) 96 Energiewerte; heute (96–191) 57 (00:00–14:00 plus laufende Viertelstunde) |
| UC3-5 | Hauptseite: Position | Skript setzt das Widget mit `insertBefore` vor `#l1` → die App steht oben unter dem Titel, nicht unten bei den Buttons |
| UC3-6 | API nicht erreichbar (keine Tarife) | Hauptseite ist `gplug_ui.html`; Daten-`div` `gp_d` mit `p` = `null`; `chart.json` antwortet |
| UC3-7 | Vergütung heute | `v` im Daten-`div` = Σ heute (`e` Wh / 1000 × `p` / 10 000) aus `chart.json` (±0.002 CHF) |

### Abnahmetests (ausführbar)

Jeder `berry`-Block unten ist ein Abnahmetest und läuft in einem **frischen Emulator** (`bash test.sh gplug ucN`). Hilfsfunktionen `T.*`: `spec/README.md`. Die App korrigieren, nie diese Blöcke — sie ändern sich nur zusammen mit der Tabelle oben.

<details><summary>Testcode (2 Blöcke)</summary>

```berry
# UC3 — 3-Tage-Grafik im WebUI

import string

T.test("UC3-1 Hauptseite: Grafik (SVG) und Datenabruf von gplug/chart.json", def ()
  T.sekunden(60)
  var h = T.hauptseite()
  T.enthaelt(h, "<svg", "SVG-Element")
  T.enthaelt(h, "gplug/chart.json", "Datenabruf im Skript")
  T.check(string.find(h, "<!-- gplug_ui.html") >= 0,
    "Die Hauptseite ist nicht die vorgegebene gplug/gplug_ui.html — Datei aus der .tapp lesen und senden, kein eigenes HTML (spec/uc3-webui.md, „Vorgegeben“)")
  T.check(size(h) < 10000, "Hauptseiten-Anteil zu gross: " + str(size(h)) + " Byte (max. 10000)")
end)

# Momentanwerte: web_sensor() liefert ein unsichtbares <div id='gp_d' data-v='{json}'>
def momentan()
  var s = T.sensor()
  var i = string.find(s, "data-v='")
  if i < 0 return nil end
  var j = string.find(s, "'", i + 8)
  return json.load(s[i + 8 .. j - 1])
end

T.test("UC3-2 Momentanwerte: Tarif jetzt, Einspeisung/Bezug/Vergütung heute — klein und ohne Grafik", def ()
  var s = T.sensor()
  T.enthaelt(s, "id='gp_d'", "Daten-div gp_d")
  T.check(string.find(s, "<svg") < 0 && string.find(s, "<script") < 0, "Grafik/Skript gehört nicht in web_sensor()")
  T.check(size(s) < 400, "web_sensor()-Ausgabe zu gross: " + str(size(s)) + " Byte (max. 400, läuft alle ~2 s)")
  var m = momentan()
  T.check(isinstance(m, map), "data-v ist kein JSON-Objekt")
  var d = T.chart()
  var q = (T.jetzt() % 86400) / 900
  T.eq(m['p'], d['p'][96 + q], "p = Tarif der laufenden Viertelstunde")
  var e = 0
  var b = 0
  for i: 96 .. 191
    if d['e'][i] != nil e += d['e'][i] end
    if d['b'][i] != nil b += d['b'][i] end
  end
  T.nahe(m['e'], e, 1, "e = Einspeisung heute (Wh)")
  T.nahe(m['b'], b, 1, "b = Bezug heute (Wh)")
  T.check(!m.contains('k'), "keine Kosten-/Tarifangabe für den Bezug (Bezugstarif unbekannt)")
  T.check(m.contains('v'), "v = Vergütung heute fehlt")
end)

T.test("UC3-3 chart.json: Viertelstunden ab gestern 00:00 — Preise bis morgen, Einspeisung, Bezug", def ()
  var r = T.http("/gplug/chart.json")
  T.eq(r['mime'], "application/json", "Content-Type")
  var d = json.load(r['body'])
  T.eq(type(d['p']), 'string', "p als Base64-Text")
  d = T.chart()
  T.eq(d['t'], (T.heute() - 1) * 86400, "t = gestern 00:00 (lokale Epoch)")
  T.nahe(d['n'], T.jetzt(), 1, "n = jetzt (lokale Epoch)")
  T.eq(size(d['p']), 288, "Anzahl Preiswerte (gestern, heute, morgen)")
  T.eq(size(d['e']), 192, "Anzahl Energiewerte (gestern, heute)")
  T.eq(size(d['b']), 192, "Anzahl Bezugswerte (gestern, heute)")
  T.check(!d.contains('k') && !d.contains('m'), "keine weiteren Felder (kein Bezugstarif)")
  T.check(size(r['body']) < 2000, "chart.json zu gross: " + str(size(r['body'])) + " Byte")
end)

T.test("UC3-4 Nach zwei Tagen sind gestern vollständig und heute bis jetzt gefüllt (inkl. laufender Viertelstunde)", def ()
  T.bis(0, 10)
  T.bis(0, 10)
  T.bis(14, 0, 10)
  var d = T.chart()
  var g = 0
  for i: 0 .. 95 if d['e'][i] != nil g += 1 end end
  T.eq(g, 96, "Energiewerte gestern")
  var h = 0
  for i: 96 .. 191 if d['e'][i] != nil h += 1 end end
  for i: 96 + 57 .. 191
    T.check(d['e'][i] == nil, "Wert in der Zukunft bei Index " + str(i) + " (jetzt 14:00 = Index 96 + 56, danach leer)")
  end
  T.check(d['e'][96 + 56] != nil,
    "laufende Viertelstunde 14:00 leer — gehört an Index 96 + 56 (heute = 96 + Viertelstunde, UC2-6)")
  T.eq(h, 57, "Energiewerte heute 00:00–14:00 plus laufende Viertelstunde")
end)

T.test("UC3-7 Momentanwert v = Vergütung heute aus Einspeisung × Tarif", def ()
  var m = momentan()
  var d = T.chart()
  var chf = 0.0
  for i: 96 .. 191
    if d['e'][i] != nil && d['p'][i] != nil chf += d['e'][i] / 1000.0 * d['p'][i] / 10000.0 end
  end
  T.check(chf > 0, "Simulation: heute keine Vergütung")
  T.nahe(m['v'], chf, 0.002, "v = Vergütung heute (CHF)")
end)

T.test("UC3-5 Hauptseite: das Skript verschiebt die App vor die Sensortabelle #l1 (oben unter dem Titel)", def ()
  var h = T.hauptseite()
  T.check(string.find(h, "insertBefore") >= 0 && string.find(h, "'l1'") >= 0,
    "Tasmota zeigt web_add_main_button() unten bei den Buttons an. Das Skript muss das Widget vor #l1 setzen: "
    + "l1=document.getElementById('l1'); l1.parentNode.insertBefore(w,l1) (spec/uc3-webui.md, Skill tasmota-berry \"Wo die App erscheint\")")
end)
```

```berry
# UC3 — WebUI ohne Tarife (BKW-API nicht erreichbar)

import string

T.netz("error")

T.test("UC3-6 Ohne Tarife: Hauptseite, Daten-div und chart.json funktionieren", def ()
  T.sekunden(60)
  T.check(string.find(T.hauptseite(), "<!-- gplug_ui.html") >= 0, "Hauptseite ohne gplug_ui.html")
  var s = T.sensor()
  T.enthaelt(s, "id='gp_d'", "Daten-div gp_d")
  T.enthaelt(s, '"p":null', "p = null ohne Tarif")
  T.eq(T.http("/gplug/chart.json")['code'], 200, "chart.json ohne Tarife")
end)
```

</details>
