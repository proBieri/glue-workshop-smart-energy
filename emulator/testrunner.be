# testrunner.be — führt eine Testdatei gegen die App im Emulator aus
#
#   berry -m emulator/mock emulator/testrunner.be <app.be> <fs_dir> <test.be>
#
# Ablauf: Emulator laden, Uhr auf Mi 11.11.2026 10:00 (MEZ) stellen,
# BKW-API als Fixture, dann die Testdatei. Die App wird erst beim ersten T-Aufruf geladen,
# der sie braucht (Zeit, Web, Befehl, Dateien lesen, Abrufe) — was ein Block vorher einstellt
# (T.netz, T.schreiben, T.zaehler_…), gilt so schon beim Start der App, wie auf dem Gerät.
# Die Testdatei nutzt das globale Objekt `T` (siehe unten). Jede Testdatei
# läuft in einem frischen Prozess mit leerem Dateisystem.

import string
import json
import os

var _app = _argv[1]
# vom Emulator (emu.be) zur Laufzeit gesetzte Globals — vorher deklarieren,
# weil Berry beim Kompilieren jeden Namen kennen muss
var _emu, _emu_fopen, _emu_days_from_civil, _emu_time_dump, _emu_tz_offset, _emu_bkw_fixture, gc
compile((size(_argv) > 4 ? _argv[4] : "emulator/mock") + "/emu.be", "file")()
_emu.fs_root = _argv[2]
_emu.set_clock(_emu_days_from_civil(2026, 11, 11) * 86400 + 9 * 3600)
_emu.fetch_mode = "fixture"

class _Test
  var ok, fehler, fehler_start, geladen

  def init() self.ok = 0 self.fehler = 0 self.geladen = false end

  # App laden wie beim Booten — einmal, beim ersten Aufruf, der sie braucht
  def laden()
    if self.geladen return end
    self.geladen = true
    if !_emu.load_app(_app)
      print("  FEHLER App konnte nicht geladen werden")
      os.exit(1)
    end
    _emu.dispatch("autoexec")
    _emu.dispatch("web_add_handler")
  end

  # --- Testfälle ---
  def test(name, f)
    var ex0 = _emu.exceptions
    try
      f()
      if _emu.exceptions > ex0
        raise "assert_failed", str(_emu.exceptions - ex0) + " Exception(s) in der App (siehe BRY:-Zeilen oben)"
      end
      print("  OK    " + name)
      self.ok += 1
    except "assert_failed" as e, m
      print("  FEHLER " + name + "\n         " + str(m))
      self.fehler += 1
    except .. as e, m
      print("  FEHLER " + name + "\n         Exception im Test: " + str(e) + ": " + str(m))
      import debug
      debug.traceback()
      self.fehler += 1
    end
  end

  # --- Prüfungen ---
  def check(c, msg) if !c raise "assert_failed", msg end end
  def eq(a, b, msg)
    if a != b raise "assert_failed", msg + " — erwartet: " + str(b) + ", erhalten: " + str(a) end
  end
  def nahe(a, b, tol, msg)
    if a == nil || b == nil || (a - b > tol) || (b - a > tol)
      raise "assert_failed", msg + " — erwartet: " + str(b) + " ±" + str(tol) + ", erhalten: " + str(a)
    end
  end
  def enthaelt(s, teil, msg)
    if s == nil || string.find(str(s), teil) < 0
      raise "assert_failed", msg + " — '" + teil + "' fehlt"
    end
  end

  # --- Zeit ---
  def sekunden(s) self.laden() _emu.advance(int(s) * 1000) end
  def stunden(h) self.laden() _emu.advance(int(h * 3600) * 1000) end
  # bis zur nächsten lokalen Uhrzeit hh:mm:ss vorspulen
  def bis(hh, mm, ss)
    self.laden()
    if ss == nil ss = 0 end
    var loc = _emu.local()
    var ziel = (loc / 86400) * 86400 + hh * 3600 + mm * 60 + ss
    if ziel <= loc ziel += 86400 end
    _emu.advance((ziel - loc) * 1000)
  end
  def jetzt() return _emu.local() end
  def heute() return _emu.local() / 86400 end
  def datum(tag)
    var t = _emu_time_dump(tag * 86400)
    return string.format("%04i-%02i-%02i", t['year'], t['month'], t['day'])
  end

  # --- Web ---
  def hauptseite()
    self.laden()
    _emu.web_out = []
    _emu.req_args = {}
    _emu.dispatch("web_add_main_button")
    return _emu.web_out.concat()
  end
  def sensor()
    self.laden()
    _emu.web_out = []
    _emu.req_args = {'m': '1'}
    _emu.dispatch("web_sensor")
    return _emu.web_out.concat()
  end
  def http(pfad)
    self.laden()
    for r: _emu.routes
      if r[0] == pfad && (r[2] == 0 || r[2] == 1)
        _emu.web_out = []
        _emu.web_code = 200
        _emu.web_mime = "text/html"
        _emu.req_args = {}
        _emu.call_safe(r[1], "webserver " + pfad)
        return {'code': _emu.web_code, 'mime': _emu.web_mime, 'body': _emu.web_out.concat()}
      end
    end
    return {'code': 404, 'mime': 'text/plain', 'body': ''}
  end
  def json(pfad)
    var r = self.http(pfad)
    self.eq(r['code'], 200, "HTTP-Status von " + pfad)
    return json.load(r['body'])
  end
  # /gplug/chart.json mit dekodierten Reihen: p, e, b als Listen von int oder nil
  # (Base64, int16 little-endian, 0x8000 = leer; spec/uc3-webui.md)
  def chart()
    var d = self.json("/gplug/chart.json")
    var V = "chart.json (spec/uc3-webui.md): "
    if !isinstance(d, map) raise "assert_failed", V + "kein JSON-Objekt" end
    var soll = {'p': 288, 'e': 192, 'b': 192}
    for k: ['p', 'e', 'b']
      var l = []
      var w = d.find(k)
      if w == nil && k == 'p'
        raise "assert_failed", V + "Feld 'p' fehlt — erwartet: Base64-Text der 288 int16-Preise (gestern, heute, morgen; bytes.tob64())"
      end
      if w != nil && type(w) != 'string'
        raise "assert_failed", V + "'" + k + "' muss Base64-Text sein (int16 little-endian, 0x8000 = leer, bytes.tob64()), erhalten: " + (type(w) == "instance" ? classname(w) : type(w))
      end
      if w != nil
        var x = bytes().fromb64(w)
        if size(x) != soll[k] * 2
          raise "assert_failed", V + "'" + k + "' muss " + str(soll[k]) + " Werte (" + str(soll[k] * 2) + " Byte) enthalten, erhalten: " + str(size(x)) + " Byte"
        end
        var i = 0
        while i < size(x) / 2
          var v = x.get(i * 2, 2)
          l.push(v == 0x8000 ? nil : (v >= 32768 ? v - 65536 : v))
          i += 1
        end
      end
      d[k] = l
    end
    return d
  end

  # --- Befehle, Dateien, Zähler, Netz ---
  def cmd(zeile)
    self.laden()
    var r = _emu.exec_cmd(zeile)
    var m = json.load(r)
    return m != nil ? m : r
  end
  def datei(name)
    self.laden()
    try
      var f = _emu_fopen(_emu.fs_path(name), "r")
      var s = f.read()
      f.close()
      return s
    except ..
      return nil
    end
  end
  def dateien()
    self.laden()
    import path
    return path.listdir("/")
  end
  def schreiben(name, inhalt)
    var f = _emu_fopen(_emu.fs_path(name), "w")
    f.write(inhalt)
    f.close()
  end
  def eo_wh() return _emu.meter.eo_wh end
  def ei_wh() return _emu.meter.ei_wh end
  def zaehler_an(an) _emu.meter.enabled = an end
  def zaehler_null(an) _emu.meter.null_an = an end   # alle Werte 0 wie Tasmota-SML vor dem ersten Telegramm
  # Zählerstand springen lassen (Wh): negativ = Zählertausch, gross positiv = Messfehler
  def zaehler_sprung(ei, eo)
    _emu.meter.ei_wh += ei
    _emu.meter.eo_wh += eo
  end
  # Tarifregister statt Ei/Eo; namen = [Bezug T1, Bezug T2, Einsp. T1, Einsp. T2], in_wh = Wh statt kWh
  def zaehler_tarife(an, namen, in_wh)
    _emu.meter.tarife = an
    if namen != nil _emu.meter.namen = namen end
    _emu.meter.in_wh = in_wh == true
  end
  def netz(modus) _emu.fetch_mode = modus end      # "fixture" | "error"
  # Neustart wie auf dem gPlug: App neu laden, Dateisystem bleibt. uhr_ab = Sekunden bis die
  # Uhr (NTP) gültig ist — vorher liefert tasmota.rtc() nur die Sekunden seit dem Start (~0),
  # denn Tasmota lädt die .tapp vor NTP. Cron und Timer laufen auf der Emulator-Zeit weiter.
  def neustart(uhr_ab)
    self.geladen = true                   # Neustart lädt selbst (auch als erster Start)
    _emu.drivers = [] _emu.crons = [] _emu.timers = [] _emu.cmds = {} _emu.routes = [] _emu.rules = []
    _emu.boot_utc = _emu.utc
    _emu.frac_ms = 0
    _emu.uhr_ab = uhr_ab ? _emu.utc + uhr_ab : 0
    if !_emu.load_app(_app) raise "assert_failed", "App konnte nach dem Neustart nicht geladen werden" end
    _emu.dispatch("autoexec")
    _emu.dispatch("web_add_handler")
  end
  def abrufe() self.laden() return _emu.fetch_count end
end

var T = _Test()

print("App:   " + _app)
print("Test:  " + _argv[3])

compile(_argv[3], "file")()
T.laden()                                 # Block ohne T-Aufruf: App trotzdem einmal laden

print(string.format("        %i OK, %i Fehler", T.ok, T.fehler))
os.exit(T.fehler > 0 ? 1 : 0)
