# pruefung.be — prüft die Beispiele aus SKILL.md (Skill tasmota-berry) im Emulator
#
#   docker compose run --rm tools bash -c './build.sh >/dev/null && mkdir -p /tmp/fs &&
#     berry -m emulator/mock emulator/testrunner.be build/autoexec.be /tmp/fs .claude/skills/tasmota-berry/pruefung.be emulator/mock'
#
# Ändert sich SKILL.md, diese Datei mitziehen.

import string
import json

T.test("Sprache: Zahlen, Strings, Listen, Maps, Klassen", def ()
  T.nahe(real("3.5") + 1, 4.5, 0.001, "real()")
  T.eq(int("42"), 42, "int()")
  T.eq(int(3.9), 3, "int() schneidet ab")
  T.eq(7 / 2, 3, "int / int schneidet ab")
  T.nahe(7 / 2.0, 3.5, 0.001, "int / real")
  var g = / x -> x * 2
  T.eq(g(4), 8, "Lambda")
  var summe = 0
  for i: 0 .. 2 summe += i end
  T.eq(summe, 3, "for-Bereich inklusive Ende")
  var s = "2026-11-11T10:00:00"
  T.eq(s[0 .. 3], "2026", "Slice inklusive")
  T.eq(s[11 ..], "10:00:00", "Slice bis Ende")
  T.eq(string.find(s, "T"), 10, "string.find")
  T.eq(string.find(s, "x"), -1, "string.find ohne Treffer")
  T.eq(size(string.split("a;b;c", ";")), 3, "string.split")
  T.eq(string.format("%i Wh, %.2f CHF, %s, %02i", 5, 1.5, "a", 7), "5 Wh, 1.50 CHF, a, 07", "string.format")
  T.eq(string.tr("a\r\n", "\r\n", ""), "a", "string.tr entfernt Zeichen")
  T.check(string.startswith("abc", "ab"), "string.startswith")
  var l = []
  l.push(1) l.push(2)
  T.eq(l.concat(","), "1,2", "list.concat")
  var m = {"a": 1}
  T.eq(m.find("c", 0), 0, "map.find mit Standardwert")
  T.check(m.contains("a") && isinstance(m, map) && isinstance(l, list), "contains/isinstance")
  class Zaehler
    var stand
    def init() self.stand = 0 end
    def plus(n) self.stand += n return self.stand end
    static def name() return "Z" end
  end
  var z = Zaehler()
  T.eq(z.plus(5), 5, "Klasse")
  T.eq(Zaehler.name(), "Z", "static def")
  var fehler = nil
  try int("x") + nil except .. as e, msg fehler = e end
  T.check(fehler != nil, "try/except fängt Fehler")
end)

T.test("JSON und bytes", def ()
  T.eq(json.load('{"a":1}')["a"], 1, "json.load")
  T.eq(json.load("kein json"), nil, "json.load ungültig → nil")
  T.eq(json.dump({"l": [1, nil]}), '{"l":[1,null]}', "json.dump")
  var b = bytes(-192)
  T.eq(size(b), 192, "bytes(-n)")
  b.set(0, 0x8000, 2)
  b.set(2, -5 & 0xFFFF, 2)
  T.eq(b.get(0, 2), 32768, "get ohne Vorzeichen")
  T.eq(b.geti(2, 2), -5, "geti mit Vorzeichen")
  T.eq(size(b[0 .. 9]), 10, "Slice")
  T.eq(size(b + b[0 .. 9]), 202, "aneinanderhängen")
  T.eq(bytes().fromb64(b.tob64()), b, "Base64 hin und zurück")
  T.eq(bytes(b.tohex()), b, "Hex hin und zurück")
end)

# Treiber, Route und Befehl wie in der Referenz
def demo_json()
  import webserver
  webserver.content_open(200, "application/json")
  webserver.content_send('{"wert":')
  webserver.content_send(str(42))
  webserver.content_send('}')
  webserver.content_close()
end

class DemoApp
  def web_add_handler()
    import webserver
    webserver.on("/demo.json", / -> demo_json(), webserver.HTTP_GET)
  end
  def web_add_main_button()
    import webserver
    webserver.content_send("<div id='demo' style='display:none'>Demo</div>")
    webserver.content_send("<script>var w=document.getElementById('demo'),l1=document.getElementById('l1');if(w&&l1&&l1.parentNode)l1.parentNode.insertBefore(w,l1);if(w)w.style.display='';</script>")
  end
  def web_sensor()
    tasmota.web_send("{s}Demo{m}42 W{e}")
  end
  def save_before_restart() end
end
var demo_app = DemoApp()
tasmota.add_driver(demo_app)
tasmota.add_cmd("DemoInfo", def (cmd, idx, payload, payload_json)
  tasmota.resp_cmnd('{"DemoInfo":{"ok":true}}')
end)
var demo_cron = 0
tasmota.add_cron("0 */15 * * * *", def () demo_cron += 1 end, "demo_cron")
var demo_timer = 0
tasmota.set_timer(20000, def () demo_timer += 1 end, "demo_timer")

T.test("Tasmota: Zeit, Cron, Timer, Treiber, Route, Befehl", def ()
  var r = tasmota.rtc()
  T.check(r["utc"] > 1700000000, "rtc utc gültig")
  T.eq(r["local"] / 86400, T.heute(), "Tag = lokal / 86400")
  T.check(r["local"] - r["utc"] == 3600, "Offset = local - utc (Winter 3600)")
  var t = tasmota.time_dump(r["local"])
  T.check(t.contains("year") && t.contains("weekday"), "time_dump")
  T.eq(size(tasmota.time_str(r["local"])), 19, "time_str")
  T.bis(10, 30, 5)
  T.eq(demo_cron, 2, "Cron :15 und :30")
  T.eq(demo_timer, 1, "Timer einmal")
  T.check(type(tasmota.read_sensors()) == "string", "read_sensors liefert Text")
  demo_app.web_add_handler()      # Tasmota ruft das beim Webserver-Start; der Prüftreiber kam später
  T.eq(T.json("/demo.json")["wert"], 42, "eigene Route")
  T.enthaelt(T.hauptseite(), "id='demo'", "web_add_main_button")
  T.enthaelt(T.hauptseite(), "insertBefore(w,l1)", "Widget vor #l1 verschieben")
  T.enthaelt(T.sensor(), "42 W", "web_sensor")
  T.eq(T.cmd("DemoInfo")["DemoInfo"]["ok"], true, "Befehl")
  T.check(tasmota.memory().contains("heap_free"), "tasmota.memory")
end)

T.test("Dateien, path, persist, Datei stückweise durchsuchen", def ()
  var f = open("/demo.txt", "w")
  f.write("Zeile 1\nZeile 2\n")
  f.close()
  f = open("/demo.txt", "r")
  T.eq(f.read(1024), "Zeile 1\nZeile 2\n", "read")
  T.eq(f.read(1024), "", "read am Ende")
  f.close()
  f = open("/demo.txt", "r")
  T.eq(f.readline(), "Zeile 1\n", "readline")
  f.close()
  import path
  T.check(path.listdir("/").find("demo.txt") != nil, "listdir ohne /")
  # grosse Datei: Muster über Stückgrenzen hinweg finden
  f = open("/demo.tmp", "w")
  var i = 0
  while i < 400 f.write('{"start_timestamp":"x","value":1},') i += 1 end
  f.close()
  def demo_suche(name, muster)
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
      var k = size(s) - size(muster) + 1
      if k < pos k = pos end
      rest = k < size(s) ? s[k ..] : ""
      if size(teil) == 0 break end
    end
    f.close()
    return treffer
  end
  T.eq(demo_suche("/demo.tmp", "start_timestamp"), 400, "alle Treffer trotz 1-kB-Stücken")
  # BKW-Format mit Leerzeichen und Zeilenumbrüchen, 96 Einträge (> 1 kB, Grenzen mitten im Eintrag)
  f = open("/demo.tmp", "w")
  f.write('{\n  "publication_timestamp": "2026-11-10T16:40:00Z",\n  "prices": [\n')
  var j = 0
  while j < 96
    var t = 1793660400 + j * 900
    f.write(string.format('    {\n      "start_timestamp": "%s",\n      "end_timestamp": "x",\n      "feed_in": [ { "unit": "CHF_kWh", "value": %s } ]\n    }%s\n',
      tasmota.time_str(t) + "Z", j == 5 ? "-0.05" : "0.1", j < 95 ? "," : ""))
    j += 1
  end
  f.write("  ]\n}\n")
  f.close()
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
  var summe_w = 0.0
  var erste = nil
  var letzte = nil
  var anz = demo_eintraege("/demo.tmp", def (zeit, wert) summe_w += wert if erste == nil erste = zeit end letzte = zeit end)
  T.eq(anz, 96, "96 Einträge trotz 1-kB-Stücken, keine doppelt")
  T.nahe(summe_w, 95 * 0.1 - 0.05, 0.0001, "Werte inkl. negativem")
  T.eq(erste, tasmota.time_str(1793660400) + "Z", "erster Zeitstempel")
  T.eq(letzte, tasmota.time_str(1793660400 + 95 * 900) + "Z", "letzter Zeitstempel")
  T.eq(tasmota.strptime(erste, "%Y-%m-%dT%H:%M:%SZ")["epoch"], 1793660400, "strptime → epoch")
  path.remove("/demo.tmp")
  path.remove("/demo.txt")
  T.check(!path.exists("/demo.txt"), "path.remove/exists")
  import persist
  persist.demo_tag = 20768
  persist.save()
  T.eq(persist.find("demo_tag", 0), 20768, "persist")
end)

def demo_monat(name)
  if size(name) != 17 || name[0 .. 5] != "gplug_" || name[13 ..] != ".csv" return nil end
  return int(name[6 .. 9]) * 12 + int(name[11 .. 12])
end
def demo_sortieren(l)
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

T.test("Listen: kein sort(), Monatsnummer, Insertion-Sort", def ()
  var fehler = nil
  try [2, 1].sort() except .. as e fehler = e end
  T.eq(fehler, "attribute_error", "l.sort() gibt es nicht")
  T.eq(demo_monat("gplug_2026-09.csv"), 2026 * 12 + 9, "Monatsnummer")
  T.eq(demo_monat("gplug_preise.json"), nil, "fremde Datei")
  T.check(demo_monat("gplug_2026-08.csv") <= 2026 * 12 + 11 - 3, "August löschen (Nov, 3 Monate)")
  T.check(demo_monat("gplug_2026-09.csv") > 2026 * 12 + 11 - 3, "September behalten")
  T.eq(demo_sortieren([5, 3, 9, 1]), [1, 3, 5, 9], "Zahlen")
  T.eq(demo_sortieren(["gplug_2026-11.csv", "gplug_2026-07.csv"]), ["gplug_2026-07.csv", "gplug_2026-11.csv"], "Strings")
  T.eq(demo_sortieren([]), [], "leere Liste")
end)

T.test("Sprache kompakt (ersetzt die allgemeine Berry-Referenz)", def ()
  import string
  import math
  # Literale, Typen, Umwandeln
  T.eq(0x80, 128, "Hex-Literal")
  T.nahe(1.1e-3, 0.0011, 0.00001, "Exponent")
  T.eq(size("ä"), 2, "\\u als UTF-8")
  T.eq(type([]), "instance", "Liste ist instance")
  T.check(isinstance([], list) && isinstance({}, map), "isinstance")
  T.eq(type(def () end), "function", "type function")
  T.eq(int("12.7"), 12, "int('12.7')")
  T.eq(int("abc"), 0, "int('abc') = 0 ohne Fehler")
  T.eq(real("x"), 0, "real('x') = 0")
  T.eq(bool("false"), true, "bool('false') = true")
  # Rechnen, Bits, Vorrang
  T.eq(-7 / 2, -3, "int / int zur Null hin")
  T.eq(-7 % 3, -1, "Rest mit Vorzeichen")
  T.check(2147483647 + 1 < 0, "int-Überlauf wird negativ")
  T.eq([5 & 3, 5 | 3, 5 ^ 3, ~0, 1 << 4, 256 >> 4], [1, 7, 6, -1, 16, 16], "Bits")
  T.eq(1 + 2 * 3, 7, "* vor +")
  var n
  T.check((n := 5) > 3 && n == 5, "Walrus :=")
  # Text
  T.eq("a" .. 1, "a1", "..")
  T.eq("ab" * 2, "abab", "String * n")
  var fehler = nil
  try var s = "a" + 1 except .. as e fehler = e end
  T.eq(fehler, "type_error", "'a' + 1")
  var x = 3.14159
  T.eq(f"{x:.2f} kWh", "3.14 kWh", "f-String")
  T.eq(format("%i Wh", 5), "5 Wh", "format()")
  T.eq(string.replace("hello", "ll", "xx"), "hexxo", "string.replace")
  T.eq(string.count("hello", "l"), 2, "string.count")
  T.check(string.endswith("hello", "lo") && string.startswith("hello", "HE", true), "endswith, startswith ohne Gross/klein")
  T.eq(string.tolower("AB"), "ab", "tolower")
  T.eq(string.byte("A"), 65, "byte")
  T.eq(string.char(66), "B", "char")
  T.eq(string.split("hello", 2), ["he", "llo"], "split an Position")
  # Bereiche, Block
  var r = range(0, 5)
  T.eq([r.lower(), r.upper()], [0, 5], "range")
  T.eq((10 ..).lower(), 10, "offener Bereich")
  var aussen = 0
  do var innen = 2 aussen = innen end
  T.eq(aussen, 2, "do-Block")
  # Listen, Maps
  var l = [1, 2]
  l.insert(1, 5)
  l.remove(0)
  T.eq(l, [5, 2], "insert, remove(Index)")
  T.eq([1, 2, 3].find(3), 2, "find")
  T.eq([1, 2, 3].find(9), nil, "find ohne Treffer")
  var c = l.copy()
  l.reverse()
  T.eq([l, c], [[2, 5], [5, 2]], "reverse, copy")
  var g = [1]
  g.resize(3)
  T.eq(g, [1, nil, nil], "resize")
  var h = [1, 2, 3]
  h[-1] = 9
  T.eq(h, [1, 2, 9], "negativer Index")
  T.eq([1, 2, 3, 4][1 .. -2], [2, 3], "Slice")
  T.eq([1] + [2], [1, 2], "Liste +")
  var k = [1]
  k .. 2
  T.eq(k, [1, 2], "Liste ..")
  var m = {"a": 1}
  T.eq([m.insert("a", 2), m.insert("b", 3), m["a"]], [false, true, 1], "map.insert überschreibt nicht")
  # Funktionen
  def zaehler(s) var z = s return def () z += 1 return z end end
  var f = zaehler(0)
  f()
  T.eq(f(), 2, "Closure")
  def rest(a, *r) return size(r) end
  T.eq(rest(1, 2, 3), 2, "variable Argumente")
  def summe(a, b, c) return a + b + c end
  T.eq(call(summe, 1, [2, 3]), 6, "call()")
  # Klassen
  class Basis var x def init(x) self.x = x end end
  class Kind : Basis
    static var MAX = 3
    def init() super(self).init(7) end
    def tostring() return "Kind " + str(self.x) end
  end
  T.eq(Kind().x, 7, "super(self).init")
  T.eq(Kind.MAX, 3, "static var")
  T.eq(str(Kind()), "Kind 7", "tostring")
  # Fehler
  var t = nil
  try raise "mein_fehler", "Text" except "mein_fehler" as e, msg t = e + ":" + msg end
  T.eq(t, "mein_fehler:Text", "raise mit Text")
  try raise "b" except "a", "b" as e t = e end
  T.eq(t, "b", "except mehrere Namen")
  try assert(false, "x") except .. as e t = e end
  T.eq(t, "assert_failed", "assert")
  # math
  T.eq([math.abs(-5), math.floor(3.7), math.ceil(3.2), math.round(3.5), math.min(1, 2), math.max(1, 2)], [5, 3, 4, 4, 1, 2], "math")
  T.eq(math.imax, 2147483647, "math.imax")
  T.check(math.isnan(math.nan), "math.isnan")
end)

T.test("Puffer mit Leer-Marker (demo_puffer, demo_wert, demo_setzen, demo_anzahl)", def ()
  def demo_puffer(n)
    var b = bytes(-2 * n)
    for i: 0 .. n - 1 b.set(i * 2, 0x8000, 2) end
    return b
  end
  def demo_wert(b, i) return b.get(i * 2, 2) == 0x8000 ? nil : b.geti(i * 2, 2) end
  def demo_setzen(b, i, v) b.set(i * 2, v == nil ? 0x8000 : v, 2) end
  def demo_anzahl(b, von, bis)
    var n = 0
    for i: von .. bis if demo_wert(b, i) != nil n += 1 end end
    return n
  end
  var p = demo_puffer(288)
  T.eq(size(p), 576, "Grösse")
  T.eq(demo_anzahl(p, 0, 287), 0, "neuer Puffer ist leer")
  T.eq(size(bytes(-4)), 4, "bytes(-n) hat n Byte")
  T.eq(bytes(-4).get(0, 2), 0, "bytes(-n) startet mit 0 (nicht leer)")
  demo_setzen(p, 96, 2300)
  demo_setzen(p, 97, -150)
  demo_setzen(p, 98, 0)
  T.eq([demo_wert(p, 96), demo_wert(p, 97), demo_wert(p, 98), demo_wert(p, 99)], [2300, -150, 0, nil], "Werte, 0 ist ein Wert")
  T.eq(demo_anzahl(p, 96, 191), 3, "anzahl")
  demo_setzen(p, 96, nil)
  T.eq(demo_wert(p, 96), nil, "wieder leer")
  T.eq(p.geti(96 * 2, 2), -32768, "geti liefert für den Marker -32768")
  T.check(p.geti(96 * 2, 2) != 0x8000, "darum geti nicht mit 0x8000 vergleichen")
  T.eq(size(p[0 .. 383].tob64()), 512, "erste 192 Werte als Base64")
end)

# Vorwärts-Deklaration (SKILL.md „Reihenfolge in der Datei“): global wie in der App
var demo_vw_b
def demo_vw_a() return "a->" + demo_vw_b() end
def demo_vw_b() return "b" end
def demo_vw_zaehlen(n) return n > 0 ? demo_vw_zaehlen(n - 1) + 1 : 0 end

T.test("Reihenfolge: Vorwärts-Deklaration mit var, Rekursion", def ()
  T.eq(demo_vw_a(), "a->b", "var oben, def unten")
  T.eq(demo_vw_zaehlen(3), 3, "Rekursion ohne Vorwärts-Deklaration")
  var fehler = nil
  try compile("def demo_x() return demo_y() end def demo_y() return 1 end") except .. as e, m fehler = m end
  T.check(fehler != nil && string.find(fehler, "undeclared") >= 0, "ohne var: undeclared — " + str(fehler))
end)
