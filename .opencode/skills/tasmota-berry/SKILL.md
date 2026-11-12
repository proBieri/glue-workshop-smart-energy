---
name: tasmota-berry
description: Berry-Sprache (vollständige Kurzreferenz, ersetzt die allgemeine Berry-Doku) und Tasmota-API für gPlug-Apps (Tasmota 15.3.0, ESP32-C3) mit geprüften Beispielen — Syntaxfallen gegenüber Python/JS (real() statt float(), size() statt len(), end-Blöcke), Strings, Listen, Maps, Klassen, JSON, bytes/Base64, Zeit (rtc, time_dump), Cron und Timer, Treiber (web_add_handler mit eigener Route, web_add_main_button, web_sensor), webserver.content_*, webclient mit write_file, Dateien stückweise lesen, path, persist, Befehle (add_cmd), Liste nicht existierender Funktionen und Fehlermeldung → Ursache. Laden, bevor Berry-Code für Tasmota geschrieben, geplant oder repariert wird.
---

# Berry/Tasmota für die gPlug-App

**Vor dem ersten Code lesen.** Alles hier läuft auf dem gPlug (Tasmota 15.3.0,
ESP32-C3) und im Emulator — jedes Beispiel geprüft mit `pruefung.be` in diesem Ordner. Was hier
nicht steht, gibt es im Zweifel **nicht**: nicht raten, nicht aus Python oder
JavaScript übernehmen.

## Sprache: die häufigsten Fallen

| Falsch (Python/JS) | Richtig (Berry) |
|---|---|
| `float("3.5")`, `float(x)` | `real("3.5")`, `real(x)` |
| `len(x)` | `size(x)` |
| `x / 4` mit zwei int → abgeschnitten | `x / 4.0` oder `real(x) / 4` |
| `"a" "b"` über mehrere Zeilen | kein mehrzeiliger String; `"a" + "b"` |
| `elif` fehlt, `else if` | `if … elif … else … end` |
| `{ … }` als Block, Einrückung | jeder Block endet mit `end` |
| `null`, `None` | `nil` |
| `x ? a : b` geht, `a if c else b` nicht | `c ? a : b` |
| `s.split(",")`, `s.find("x")` | `import string` → `string.split(s, ",")`, `string.find(s, "x")` |
| `for (i=0;i<n;i++)` | `for i: 0 .. n - 1 … end` (Bereich **inklusive** Ende) |
| Funktion nach dem Aufruf definieren | **vor** der ersten Verwendung definieren (auch über Dateien hinweg); brauchen sich zwei gegenseitig: Vorwärts-Deklaration (unten) |
| `l = []` in einer Funktion (neue Variable ohne `var`) | `var l = []` — Tasmota übersetzt im strict-Modus, sonst lädt die `.tapp` nicht |
| `s = s "<b>"` (wie `"a" "b"`) | `s += "<b>"` — ohne `+` gilt `s = s`, der String wird **ohne Fehlermeldung** verworfen (`build.sh` meldet es) |
| `f.read(1024).asstring()` | `f.read(1024)` liefert schon Text (`readbytes()` liefert bytes) |
| `if cl.begin(url) != 200` | `cl.begin(url)` ohne Prüfung, Status kommt von `cl.GET()` |

```berry
var n = 0                     # Variable (global, wenn ausserhalb einer Funktion)
def quadrat(x) return x * x end
var f = def (a, b) return a + b end      # anonyme Funktion
var g = / x -> x * 2                     # Kurzform (Lambda)
if n > 0 && n < 10 print("klein") elif n == 0 print("null") else print("gross") end
while n < 3 n += 1 end
for i: 0 .. 2 print(i) end               # 0, 1, 2
for x: [10, 20] print(x) end
try
  var v = int("12")
except .. as e, m                        # e = Fehlername, m = Text
  log("GPL: Fehler " + str(m), 2)
end
```

**Reihenfolge in der Datei:** von oben nach unten — Konstanten und Puffer, Helfer, Logik, zuletzt
Start/Timer/Cron (`main.be` kommt ohnehin zuletzt). Ruft eine Funktion eine spätere auf (z.B. der
Abruf stellt den Start-Timer, der Start-Timer ruft den Abruf), den späteren Namen **oben mit
`var` ankündigen** — sonst `'demo_start' undeclared`:

```berry
var demo_start                           # Vorwärts-Deklaration: Name bekannt, Funktion folgt unten
def demo_abruf()
  if tasmota.rtc()["utc"] < 1700000000 demo_start() return end   # erlaubt dank var oben
  # … abrufen …
end
def demo_start()                         # füllt die Variable von oben
  tasmota.set_timer(5000, demo_abruf, "demo_start")
end
```

Eine Funktion, die sich selbst aufruft (Rekursion, Timer stellt sich neu), braucht das nicht.

Zahlen: `int("42")`, `real("4.2")`, `str(x)`; `int(3.9)` = 3. Ganzzahlen und `real`
sind 32 Bit — grosse Zählerstände (7654.321 kWh) als Text in Wh umrechnen, nicht über
`real`.

Strings (`import string`): `size(s)`, `s[0 .. 3]` (inklusive), `s[5 ..]` (bis Ende),
`s[i]` (ein Zeichen), `string.find(s, "x", ab)` → Position oder `-1`,
`string.split(s, ";")`, `string.format("%i Wh, %.2f CHF, %s, %02i", 5, 1.5, "a", 7)`,
`string.tr(s, "\r\n", "")` (Zeichen entfernen), `string.toupper(s)`, `string.startswith(s, "ab")`.

Listen: `var l = []`, `l.push(x)`, `l.pop()`, `size(l)`, `l[0]`, `l.concat(",")` (zu Text).
**Sortieren gibt es nicht** (`l.sort()` → `attribute_error`; andere Berry-Dokus beschreiben eine andere
Version). Meist braucht man es nicht — z.B. alte Monatsdateien: Name in eine Zahl umrechnen und vergleichen.
Wenn doch, Insertion-Sort:

```berry
def demo_monat(name)                     # "gplug_2026-09.csv" → 2026 * 12 + 9; sonst nil
  if size(name) != 17 || name[0 .. 5] != "gplug_" || name[13 ..] != ".csv" return nil end
  return int(name[6 .. 9]) * 12 + int(name[11 .. 12])
end
# behalten: die letzten 3 Monate → löschen, wenn demo_monat(name) <= jahr * 12 + monat - 3

def demo_sortieren(l)                    # sortiert l aufsteigend (Zahlen oder Strings)
  for i: 1 .. size(l) - 1
    var x = l[i]
    var j = i - 1
    while j >= 0 && l[j] > x
      l[j + 1] = l[j]
      j -= 1
    end
    l[j + 1] = x
  end
  return l
end
```

Maps: `var m = {"a": 1}`, `m["b"] = 2`, `m.find("c", 0)` (mit Standardwert),
`m.contains("a")`, `m.keys()`, `m.remove("a")`. Prüfen: `isinstance(m, map)`,
`isinstance(l, list)`, `type(s) == "string"`.

Klassen:

```berry
class Zaehler
  var stand                              # Attribute mit var deklarieren
  def init() self.stand = 0 end          # Konstruktor
  def plus(n) self.stand += n return self.stand end
  static def name() return "Z" end       # Aufruf: Zaehler.name()
end
var z = Zaehler()
z.plus(5)
```

Vererbung, statische Werte, Text-Darstellung:

```berry
class Basis
  var x
  def init(x) self.x = x end
end
class Kind : Basis                       # erbt von Basis
  static var MAX = 3                     # Kind.MAX
  def init() super(self).init(7) end     # Konstruktor der Basis aufrufen
  def tostring() return "Kind " + str(self.x) end   # für str(k) und print(k)
end
```

### Sprache kompakt

Ersetzt die allgemeine Berry-Referenz; alles mit dem Berry aus Tasmota 15.3.0 geprüft.

| Thema | Berry |
|---|---|
| Kommentare | `# Zeile`, `#- Block -#` |
| Literale | `40`, `0x80`, `3.14`, `1.1e-3`, `true`, `nil`, `'text'` oder `"text"`; Escapes `\n \t \" \\ \xhh ä` |
| Typen | `type(x)` → `"int"`, `"real"`, `"string"`, `"bool"`, `"nil"`, `"function"` — Listen und Maps sind `"instance"`: dafür `isinstance(x, list)` / `isinstance(x, map)` |
| Umwandeln | `int("12.7")` = 12, `int("abc")` = **0 ohne Fehler**, `real("x")` = 0, `str(x)`; `bool("false")` = **true** (jeder nicht leere Text) |
| Rechnen | `+ - * / %`; int / int schneidet **zur Null hin** ab (`-7 / 2` = -3, `-7 % 3` = -1); int läuft bei 2147483647 über ins Negative |
| Bits | `& \| ^ ~ << >>` |
| Vergleich, Logik | `== != < <= > >=`, `&& \|\| !` (Kurzschluss), `c ? a : b` |
| Zuweisung | `= += -= *= /= %=`, `:=` weist zu und liefert den Wert (`if (n := f()) > 0`) |
| Vorrang (hoch → tief) | `()` `[]` `.` → `- ! ~` → `* / %` → `+ -` → `<< >>` → `&` → `^` → `\|` → `..` → `< <= > >=` → `== !=` → `&&` → `\|\|` → `? :` → `=` |
| Text verbinden | `"a" + str(1)` (`"a" + 1` → `type_error`), `"a" .. 1`, `"ab" * 2` = `"abab"` |
| Formatieren | `format("%i Wh", 5)`, f-String `f"{x:.2f} kWh"` |
| Bereich | `0 .. 5` (inklusive), `10 ..` (bis Ende), `range(0, 5)` |
| Block | `do … end` (eigener Gültigkeitsbereich für `var`) |
| Funktionen | Closures (innere Funktion behält ihre Variablen), variable Argumente `def f(a, *rest)`, `call(f, 1, [2, 3])` = `f(1, 2, 3)` |
| Fehler | `raise "mein_fehler", "Text"`; `except "a", "b" as e, m`; `except ..` fängt alles; `assert(bed, "Text")`. Namen: `index_error`, `key_error`, `type_error`, `io_error`, `syntax_error`, `runtime_error`, `assert_failed` |
| `math` | `abs floor ceil round min max sqrt pow`, `math.imax`, `math.isnan(x)`, `math.pi` |

Strings, Listen und Maps — was es zusätzlich gibt:

| | |
|---|---|
| `string` | `replace(s, "ll", "xx")`, `count(s, "l")`, `endswith(s, "lo")`, `startswith(s, "HE", true)` (ohne Gross/klein), `tolower`, `toupper`, `byte("A")` = 65, `char(66)` = `"B"`, `split(s, 2)` (an Position) |
| Listen | `find(x)` → Index oder `nil`, `insert(i, x)`, `remove(i)` (Index!), `reverse()`, `copy()`, `resize(n)` (füllt mit `nil`), `l[-1]`, `l[1 .. -2]`, `l + [x]` (neue Liste), `l .. x` (hängt an), `l.keys()`, `[1, 2] == [1, 2]` |
| Maps | `insert(k, v)` → `false`, wenn `k` schon da ist (überschreibt nicht), `remove(k)`, `size()` |

Achtung: `if`, `while`, `for`, `def`, `class`, `try` brauchen je ein `end`. Fehlt eines,
meldet der Compiler `expected 'class' before 'EOS'` oder `expected 'end'` — dann die
Blöcke der genannten Datei zählen.

## JSON

```berry
import json
var m = json.load('{"a":1}')             # nil, wenn kein gültiges JSON
var s = json.dump({"a": 1, "l": [1, nil]})   # nil wird zu null
```

Grosse Antworten (> ~5 kB) **nie** mit `json.load` oder `get_string()` am Stück —
siehe Webclient.

## bytes: kompakte Zahlenreihen

```berry
var b = bytes(-192)                      # 192 Byte, mit 0 gefüllt (fixe Grösse)
b.set(0, 0x8000, 2)                      # 2 Byte ab Position 0 (little-endian)
var u = b.get(0, 2)                      # 0..65535 (ohne Vorzeichen)
var s = b.geti(0, 2)                     # -32768..32767 (mit Vorzeichen)
var teil = b[0 .. 9]                     # Kopie von Byte 0–9
var alle = b + teil                      # aneinanderhängen
var t64 = b.tob64()                      # Base64-Text, z.B. für JSON
var zurueck = bytes().fromb64(t64)
var hex = b.tohex()                      # Hex-Text (Datei), zurück: bytes(hex)
```

**Puffer mit Leer-Marker** (Tarife, Einspeisung, Bezug: int16, `0x8000` = leer) — dieses Muster
übernehmen und nur umbenennen, **nie byteweise selbst zusammensetzen** (`lo | (hi << 8)`):

```berry
def demo_puffer(n)                       # n Werte int16, alle leer
  var b = bytes(-2 * n)                  # bytes(-n) startet mit 0 — 0 ist ein Wert, nicht leer!
  for i: 0 .. n - 1 b.set(i * 2, 0x8000, 2) end
  return b
end
def demo_wert(b, i)                      # Wert (-32767..32767) oder nil = leer
  return b.get(i * 2, 2) == 0x8000 ? nil : b.geti(i * 2, 2)
end
def demo_setzen(b, i, v)                 # v = nil → leer
  b.set(i * 2, v == nil ? 0x8000 : v, 2)
end
def demo_anzahl(b, von, bis)             # gefüllte Werte von..bis (inklusive)
  var n = 0
  for i: von .. bis if demo_wert(b, i) != nil n += 1 end end
  return n
end
var demo_p = demo_puffer(288)            # gestern, heute, morgen × 96
demo_setzen(demo_p, 96, 2300)
var heute_voll = demo_anzahl(demo_p, 96, 191) == 96
```

Leer prüfen immer mit `get` (ohne Vorzeichen) `== 0x8000` — `geti` liefert für den Marker `-32768`,
der Vergleich mit `0x8000` (= 32768) ist dann nie wahr, und ein leerer Puffer gilt als voll. Den
Marker nicht über eine Funktion schreiben, die auf −32768…32767 begrenzt (aus „leer“ wird 32767).
Nur einen Teil senden: `b[0 .. 383].tob64()` (die ersten 192 Werte).

## Tasmota: Zeit, Zeitplan, Treiber

```berry
var r = tasmota.rtc()                    # {"local": Epoch lokal, "utc": Epoch UTC, …}
var jetzt = r["local"]
var tag = jetzt / 86400                  # Tage seit 1970 (lokal), z.B. 20768 — NICHT time_dump()["day"]
var tz = r["local"] - r["utc"]          # Zeitzonen-Offset in Sekunden (3600 Winter, 7200 Sommer)
var sek = jetzt % 86400                  # Sekunde des Tages
var t = tasmota.time_dump(jetzt)         # {"year","month","day","hour","min","sec","weekday"} (weekday 0 = Sonntag)
var txt = tasmota.time_str(jetzt)        # "2026-11-11T10:00:00"
tasmota.add_cron("0 */15 * * * *", def () log("GPL: Viertelstunde", 2) end, "demo_cron")
#                 s  m    h d M Wt       6 Felder, Sekunden zuerst; lokale Zeit
tasmota.remove_cron("demo_cron")
tasmota.set_timer(20000, def () log("GPL: 20 s nach Start", 2) end, "demo_timer")   # einmalig, ms
tasmota.remove_timer("demo_timer")
log("GPL: Text", 2)                      # Log (2 = Info); im Test filtern mit grep "GPL:"
```

Die Uhr ist erst nach NTP gültig: `tasmota.rtc()["utc"] > 1700000000`. Tasmota lädt die
`.tapp` **vor** NTP — beim Start darum mit einem Timer wiederholt prüfen (z.B. alle 5 s, der
Timer stellt sich selbst neu, bis die Uhr stimmt), nicht nur einmal. Erst dann Tagesbezogenes
tun (Puffer auf „heute“ schieben), sonst wird mit Tag 0 gerechnet und gespeicherte Werte gehen verloren.

Zählerstände: `tasmota.read_sensors()` liefert **Text** (wie `Status 10`), z.B.
`{"Time":"…","z":{"Pi":847,"Po":0,"Ei":7654.321,"Eo":234.567}}` — mit `string.find`
den Schlüssel suchen oder `json.load` (klein genug).

Treiber — Tasmota ruft diese Methoden selbst auf:

```berry
class DemoApp
  def web_add_handler()                  # einmal beim Start: eigene Web-Routen
    import webserver
    webserver.on("/demo.json", / -> demo_json(), webserver.HTTP_GET)
  end
  def web_add_main_button()              # einmal pro Aufruf der Hauptseite: statisches HTML/JS
    import webserver
    webserver.content_send("<div id='demo' style='display:none'>Demo</div>")
    webserver.content_send("<script>var w=document.getElementById('demo'),l1=document.getElementById('l1');if(w&&l1&&l1.parentNode)l1.parentNode.insertBefore(w,l1);if(w)w.style.display='';</script>")
  end
  def web_sensor()                       # bei jedem Poll der Hauptseite (~2 s): nur kleine Werte
    tasmota.web_send("{s}Demo{m}42 W{e}")
  end
  def save_before_restart() end          # vor einem Neustart: Daten sichern
end
var demo_app = DemoApp()
tasmota.add_driver(demo_app)             # erst danach ruft Tasmota die Methoden
```

`web_add_handler`, `web_add_main_button`, `web_sensor` gibt es **nur** als Methoden
eines Treibers — nicht als `tasmota.…`-Funktionen.

**Wo die App erscheint:** Tasmota fügt die Ausgabe von `web_add_main_button()` **unten** bei
den Buttons ein. Damit die App oben unter dem Titel steht, verschiebt das Skript sie vor die
Sensortabelle `#l1` (wie oben; zuerst unsichtbar, damit sie nicht springt). **Nicht** in `#l1`
hinein: dessen Inhalt ersetzt jeder Poll von `web_sensor()`. Prüft Test UC3-5.

## Webserver: eigene Antwort (z.B. JSON)

```berry
def demo_json()
  import webserver
  webserver.content_open(200, "application/json")
  webserver.content_send('{"wert":')
  webserver.content_send(str(42))        # in Stücken senden spart Heap
  webserver.content_send('}')
  webserver.content_close()
end
```

Parameter: `webserver.has_arg("x")`, `webserver.arg("x")`. Im Browser die Route
**relativ** holen: `fetch('demo.json')`.

## Webclient: Daten aus dem Internet

```berry
def demo_abruf(url)
  var cl = webclient()
  cl.begin(url)
  var code = cl.GET()                    # HTTP-Status, z.B. 200; < 0 = Netzwerkfehler
  var n = 0
  if code == 200 n = cl.write_file("/demo.tmp") end   # Antwort direkt in eine Datei (Byte)
  cl.close()
  return code == 200 && n > 0
end
```

Kleine Antworten: `cl.get_string()`. Grosse (die BKW-Antwort, ~21 kB): **immer**
`write_file`, dann die Datei stückweise lesen (unten). Gemessen auf dem gPlug:
`json.load` → Neustart, `get_string()` → still abgeschnitten.

## Dateien, path, persist

```berry
var f = open("/demo.txt", "w")           # "r" lesen, "w" neu schreiben, "a" anhängen
f.write("Zeile 1\nZeile 2\n")
f.close()
f = open("/demo.txt", "r")
var stueck = f.read(1024)                # höchstens 1024 Zeichen; "" am Dateiende
f.close()
f = open("/demo.txt", "r")
var zeile = f.readline()                 # inkl. "\n"; "" am Dateiende
f.close()

import path
if path.exists("/demo.txt") path.remove("/demo.txt") end
var namen = path.listdir("/")            # ["demo.csv", …] ohne führenden /

import persist                           # kleine Werte über Neustarts, als Attribute
persist.demo_tag = 20768
var d = persist.find("demo_tag", 0)      # mit Standardwert
persist.save()
```

Datei stückweise durchsuchen — ein angefangener Eintrag am Ende eines Stücks wird
ins nächste übernommen:

```berry
def demo_suche(name, muster)
  import string
  var f = open(name, "r")
  var rest = ""
  var treffer = 0
  while true
    var teil = f.read(1024)
    var s = rest + teil
    var pos = 0
    while true
      var i = string.find(s, muster, pos)
      if i < 0 break end
      treffer += 1
      pos = i + size(muster)
    end
    var k = size(s) - size(muster) + 1     # die letzten Zeichen behalten, falls das
    if k < pos k = pos end                 # Muster über die Stückgrenze geht — aber
    rest = k < size(s) ? s[k ..] : ""     # nichts, was schon gezählt wurde
    if size(teil) == 0 break end
  end
  f.close()
  return treffer
end
```

**Für die BKW-Antwort diese Funktion unverändert übernehmen** (nur umbenennen, z.B.
`uc1_eintraege`) — selbst geschriebene Parser sind in den Workshop-Läufen jedes Mal an
den Stückgrenzen gescheitert. Einträge mit mehreren Feldern stückweise lesen (Zeitstempel
und Wert) — ist ein Eintrag am Ende eines Stücks noch nicht vollständig, beginnt das
nächste Stück **ab diesem Eintrag** (nicht danach, sonst fehlen Einträge; nicht
davor, sonst werden sie doppelt gezählt):

```berry
def demo_eintraege(name, fn)             # fn(zeit, wert) für jeden Eintrag
  import string
  var f = open(name, "r")
  var rest = ""
  var n = 0
  while true
    var teil = f.read(1024)
    var s = rest + teil
    var pos = 0
    var offen = -1                       # Anfang eines unvollständigen Eintrags
    while true
      var i = string.find(s, '"start_timestamp"', pos)
      if i < 0 break end
      var q = string.find(s, '"', i + 17)                # " vor dem Zeitstempel
      var z = q < 0 ? -1 : string.find(s, '"', q + 1)    # " danach
      var v = z < 0 ? -1 : string.find(s, '"value"', z)
      var a = v < 0 ? -1 : string.find(s, ":", v)
      var b = a < 0 ? -1 : a + 1
      while b >= 0 && b < size(s) && s[b] == " " b += 1 end   # Leerzeichen nach ":"
      var e = b
      while e >= 0 && e < size(s) && string.find(",}] \n\r", s[e]) < 0 e += 1 end
      if e < 0 || e >= size(s) offen = i break end       # Rest kommt im nächsten Stück
      fn(s[q + 1 .. z - 1], real(s[b .. e - 1]))
      n += 1
      pos = e
    end
    if offen >= 0
      rest = s[offen ..]
    else
      var k = size(s) - 16               # Anfang eines Musters an der Grenze behalten
      if k < pos k = pos end
      rest = k < size(s) ? s[k ..] : ""
    end
    if size(teil) == 0 break end
  end
  f.close()
  return n
end
# Aufruf: demo_eintraege("/demo.tmp", def (zeit, wert) … end)  → Anzahl Einträge
```

Zeitstempel `"2026-11-11T09:00:00Z"` → Sekunden: `tasmota.strptime(zeit, "%Y-%m-%dT%H:%M:%SZ")["epoch"]` (UTC).

Dateien der App selbst (z.B. `gplug_ui.html` in der `.tapp`): `tasmota.wd` ist nur
**beim Laden** gesetzt — sofort in eine globale Variable übernehmen:
`var DEMO_WD = tasmota.wd`, später `open(DEMO_WD + "gplug_ui.html", "r")`.

## Befehle (Konsole, HTTP `/cm?cmnd=`, MQTT)

```berry
tasmota.add_cmd("DemoInfo", def (cmd, idx, payload, payload_json)
  tasmota.resp_cmnd('{"DemoInfo":{"ok":true}}')      # oder resp_cmnd_done() / resp_cmnd_failed()
end)
```

## Speicher (ESP32-C3, kein PSRAM)

- `tasmota.memory()` → `{"heap_free": kB, "frag": %, …}`, `tasmota.gc()` räumt auf.
- Zeitreihen in `bytes`, nicht in Listen (jeder Listeneintrag kostet ein Objekt).
- Alle Apps teilen sich einen Namensraum: globale Namen mit Präfix (`uc1_…`, `gplug_…`).

## Diese Funktionen gibt es NICHT

`tasmota.http_get`, `tasmota.timer_set`, `tasmota.webserver`, `tasmota.file_read`,
`tasmota.file_write`, `tasmota.flag_get`, `tasmota.sensor_read`, `float()`, `len()`,
`os` (auch `os.path`, `os.system` — Dateien: `import path`), `time` (beide nur im Emulator
vorhanden, nicht auf dem Gerät), alles mit `_emu_…` oder
`T.…` (Testwerkzeuge der Spec-Tests in `spec/`, nie in die App übernehmen — `build.sh` lehnt sie ab), `l.sort()`/`sort()`
(→ oben bei Listen), `string.join` (→ `liste.concat(",")`), `defined(x)` (→ `x != nil`; Globals vorher mit `var` deklarieren). Allgemeine Berry-Dokus beschreiben
mehr (z.B. `introspect.toptr`, `os`) — für die App gilt nur, was hier steht.

## Fehlersuche ohne Fehlermeldung

Läuft etwas nicht (Funktion scheint nie zu laufen, Wert bleibt `0`/`nil`), nicht raten
und nicht den Emulator lesen — eine Runde Log-Zeilen an die Entscheidungsstellen:

```berry
log("GPL: abruf noetig=" + str(noetig) + " heute=" + str(anzahl), 2)
```

```bash
./test.sh gplug uc1 2>&1 | grep -E "GPL:|FEHLER"
```

Häufige Ursache: ein Puffer startet mit `0` statt mit dem Leer-Marker (`0x8000`) und
gilt darum als „voll“; oder eine Bedingung prüft den falschen Tag (lokal vs. UTC).
Die Log-Zeilen mit dem Fix wieder entfernen.

## Fehlermeldungen → Ursache

| Meldung | Ursache |
|---|---|
| `'float' undeclared` | `real()` statt `float()` |
| `'x' undeclared` | `x` wird vor seiner Definition benutzt, oder `import` fehlt |
| `expected 'class' before 'EOS'`, `expected 'end'` | ein `end` fehlt (oder eines zu viel) |
| `unfinished string` | String über mehrere Zeilen |
| `stray '\195' in program` | Umlaut (ä, ö, ü) im Code ausserhalb eines Strings oder Kommentars — Namen nur ASCII: `zaehler`, nicht `zähler` |
| `'defined' undeclared` | `defined()` gibt es nicht — `x != nil` |
| `attribute_error: 'nil' value has no method` | Variable ist `nil` (z.B. Datei/JSON nicht gelesen) |
| `type_error: unsupported operand type(s) for +: 'string' and 'int'` | `str(x)` beim Zusammensetzen vergessen |
| Route liefert 404 | `webserver.on` nicht in `web_add_handler()` eines registrierten Treibers |
