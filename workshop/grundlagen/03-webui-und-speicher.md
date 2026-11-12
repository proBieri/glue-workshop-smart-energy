# 3 · Weboberfläche und Speicher auf dem ESP32-C3

Ausführlich im Projekt-Skill `.claude/skills/tasmota-lowmem-webui/SKILL.md`
(Claude Code lädt ihn selbst; für opencode steht die Kurzfassung in `AGENTS.md`).

## Wie Tasmotas Hauptseite funktioniert

```
Browser                                      gPlug
  │  GET /             ─────────────────────▶  web_add_main_button()   einmal pro Seitenaufruf
  │  GET /?m=1  (alle ~2 s) ────────────────▶  web_sensor()            ersetzt den Inhalt von #l1
  │  GET /gplug/chart.json (unsere Route) ──▶  webserver.on(…)          so oft wir wollen
```

- `web_sensor()` läuft **dauernd**. Alles, was dort steht, wird alle 2 s neu erzeugt
  und übertragen — und der Browser **ersetzt** den ganzen Bereich `#l1`.
- `web_add_main_button()` läuft **einmal** pro Seitenaufruf.

## Muster für die Grafik

1. **Skelett einmal senden**: SVG, CSS und JavaScript aus `web_add_main_button()`.
   Das Widget per JS als Geschwister **vor** `#l1` verschieben — sonst löscht es der
   nächste Poll:
   ```js
   var w=document.getElementById('gp_w'),l1=document.getElementById('l1');
   l1.parentNode.insertBefore(w,l1); w.style.display='';
   ```
2. **Daten separat**: eigene Route `/gplug/chart.json`, vom Browser alle 5 Minuten
   geholt (`fetch('gplug/chart.json')` — relativer Pfad). Die Werte ändern sich nur alle 15 Minuten.
3. **Rohwerte senden, im Browser rechnen**: 288 Tarife und 2 × 192 Energiewerte
   (Viertelstunden, 1 SVG-Einheit pro Wert) als Base64 der `bytes()`-Puffer — der Server
   kopiert nur, statt eine Liste mit 672 Zahlen zu bauen. Dekodieren, Vergütung,
   Skalen, Beschriftung und Tagessummen rechnet JavaScript.
4. **Momentanwerte im Poll mitliefern** (Skill §3): `web_sensor()` schickt nur ein
   unsichtbares `<div id='gp_d' data-v='{"p":…,"e":…}'>` (< 400 Byte). Ein
   MutationObserver auf `#l1` merkt, wenn Tasmota neu gepollt hat, und füllt die
   grossen Kacheln oben im Widget — ohne zweite Anfrage, immer aktuell. Tasmotas
   eigene Zeilen `{s}Name{m}Wert{e}` sind unten klein und schlecht lesbar.

## Speicher: was kostet was?

| Was | Heap | Wie lange |
|---|---|---|
| `list` mit 96 Zahlen | ~1.5–2 kB | dauernd |
| `bytes(192)` mit 96 int16 | ~0.2 kB | dauernd |
| jedes String-Literal im Code | seine Länge + Kopf | **dauernd** (gehört zum Code) |
| 5 kB HTML aus einer Datei gelesen | 5 kB | nur während des Seitenaufrufs |
| `json.load` von 21 kB | weit über 50 kB | Absturz |
| `get_string()` von 21 kB | 21 kB **am Stück** | scheitert bei Fragmentierung still |
| `write_file()` + `f.read(1024)` | ~2 kB | einmal pro Abruf |

Daraus folgt:
- Zeitreihen in **`bytes()`** speichern, 2 Byte pro Wert, `0x8000` als „kein Wert“.
  `get()` liefert vorzeichenlos → `if raw >= 32768 raw -= 65536 end`.
- Grosse statische Texte **nicht** als viele `"…" + "…"`-Literale im Code, sondern als
  Datei in der `.tapp` (`gplug_ui.html`) und beim Seitenaufruf lesen.
- Mit `float` vorsichtig: 32 Bit, ~7 Stellen. `7654.321 kWh × 1000` ist auf ±1 Wh ungenau
  → Zählerstand direkt aus dem Text in Wh umrechnen.

## Mehrere Apps teilen sich einen Speicher

Alle `.tapp` auf dem gPlug laufen in **einer** Berry-VM: gleicher Namensraum, gleicher
Heap. Auf dem Test-gPlugK lief schon `gplug_ha.tapp` (34 kB Berry-Heap); mit unserer
App waren es 55–57 kB. Darum immer **mit allen Apps** messen, und vor dem Hochladen
prüfen, ob Namen kollidieren (`Br import global … global()`).

## Messen

```
Br tasmota.memory()      → gc_heap (Berry), heap_free, frag
Br tasmota.gc()          → Bytes nach Garbage Collection
Status 11                → Heap, Berry.HeapUsed, LoadAvg
```

Fällt `gc_heap` nach `tasmota.gc()` deutlich → Müll. Bleibt er gleich → dauerhaft
belegt (Code, Puffer). Ein Leck wächst Stunde um Stunde trotz `gc()`.
