# emu.be — Tasmota-Emulator: bildet die Tasmota-Berry-API auf dem Desktop nach
#
# Wird vor der App geladen und definiert die Globals, die auf dem Gerät
# eingebaut sind: `tasmota`, `webclient`, `log`, `open` (auf ein virtuelles
# Dateisystem umgebogen). Die Module `webserver`, `persist`, `path`, `mqtt`
# liegen als eigene Dateien in diesem Verzeichnis (berry -m emulator/mock).
#
# Abgebildet ist nur, was eine gPlug-App typischerweise braucht. Verhalten
# und Signaturen folgen Tasmota 15.x (lib/libesp32/berry_tasmota). Was fehlt,
# wirft einen klaren Fehler statt still etwas Falsches zu tun.
#
# Unterschiede zum Gerät (wichtig für Heap-Messungen):
#   - Desktop-Berry nutzt 64-bit-Zeiger: Objekte sind ~1.5–2x grösser.
#   - Die Module `os` und `time` gibt es nur hier, nicht auf dem Gerät.

import string
import json
import math
import global
import introspect
import gc
import os

var _emu_fopen = open         # eingebautes open() sichern, bevor es ersetzt wird

# ---------------------------------------------------------------------------
# Datum/Zeit (proleptischer Gregorianischer Kalender, Unix-Epoch)
# ---------------------------------------------------------------------------
def _emu_days_from_civil(y, m, d)
  if m <= 2 y -= 1 end
  var era = (y >= 0 ? y : y - 399) / 400
  var yoe = y - era * 400
  var mp = (m + 9) % 12
  var doy = (153 * mp + 2) / 5 + d - 1
  var doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  return era * 146097 + doe - 719468
end

def _emu_civil(z)
  z += 719468
  var era = (z >= 0 ? z : z - 146096) / 146097
  var doe = z - era * 146097
  var yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  var y = yoe + era * 400
  var doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  var mp = (5 * doy + 2) / 153
  var d = doy - (153 * mp + 2) / 5 + 1
  var m = mp < 10 ? mp + 3 : mp - 9
  return [m <= 2 ? y + 1 : y, m, d]
end

def _emu_time_dump(ts)
  var day = ts / 86400
  var s = ts % 86400
  if s < 0 s += 86400 day -= 1 end
  var c = _emu_civil(day)
  return {'year': c[0], 'month': c[1], 'day': c[2],
          'hour': s / 3600, 'min': (s / 60) % 60, 'sec': s % 60,
          'weekday': (day + 4) % 7, 'epoch': ts}
end

def _emu_last_sunday(y, m)
  var last = _emu_days_from_civil(y, m + 1, 1) - 1
  return last - (last + 4) % 7
end

# Mitteleuropäische Zeit mit Sommerzeit (wie Tasmota "Timezone 99" in CH)
def _emu_tz_offset(utc)
  var y = _emu_civil(utc / 86400)[0]
  var start = _emu_last_sunday(y, 3) * 86400 + 3600
  var stop = _emu_last_sunday(y, 10) * 86400 + 3600
  return (utc >= start && utc < stop) ? 120 : 60
end

def _emu_strftime(fmt, ts)
  var t = _emu_time_dump(ts)
  var out = ""
  var i = 0
  while i < size(fmt)
    var c = fmt[i]
    if c == "%" && i + 1 < size(fmt)
      var k = fmt[i + 1]
      if   k == "Y" out += str(t['year'])
      elif k == "y" out += string.format("%02i", t['year'] % 100)
      elif k == "m" out += string.format("%02i", t['month'])
      elif k == "d" out += string.format("%02i", t['day'])
      elif k == "H" out += string.format("%02i", t['hour'])
      elif k == "M" out += string.format("%02i", t['min'])
      elif k == "S" out += string.format("%02i", t['sec'])
      elif k == "%" out += "%"
      else raise "value_error", "strftime: %" + k + " wird im Emulator nicht unterstützt"
      end
      i += 2
    else
      out += c
      i += 1
    end
  end
  return out
end

# ---------------------------------------------------------------------------
# Cron (6 Felder: Sekunde Minute Stunde Tag Monat Wochentag), lokale Zeit
# ---------------------------------------------------------------------------
class _EmuCron
  var f_sec, f_min, f_hour, f_dom, f_mon, f_dow

  def init(pattern)
    var parts = []
    for p: string.split(pattern, " ")
      if size(p) > 0 parts.push(p) end
    end
    if size(parts) != 6
      raise "value_error", "Cron-Muster braucht 6 Felder (Sekunde zuerst): '" + pattern + "'"
    end
    self.f_sec = self.parse(parts[0], 0, 59)
    self.f_min = self.parse(parts[1], 0, 59)
    self.f_hour = self.parse(parts[2], 0, 23)
    self.f_dom = self.parse(parts[3], 1, 31)
    self.f_mon = self.parse(parts[4], 1, 12)
    self.f_dow = self.parse(parts[5], 0, 6)
  end

  # nil = alles erlaubt, sonst Map der erlaubten Werte
  def parse(s, lo, hi)
    if s == "*" || s == "?" return nil end
    var allowed = {}
    for part: string.split(s, ",")
      var step = 1
      var sl = string.find(part, "/")
      if sl >= 0
        step = int(part[sl + 1 ..])
        part = part[0 .. sl - 1]
      end
      var a = lo
      var b = hi
      if part != "*"
        var dash = string.find(part, "-")
        if dash >= 0
          a = int(part[0 .. dash - 1])
          b = int(part[dash + 1 ..])
        else
          a = int(part)
          b = sl >= 0 ? hi : a
        end
      end
      if a < lo || b > hi || step < 1
        raise "value_error", "Cron-Feld ausserhalb des Bereichs: '" + s + "'"
      end
      var v = a
      while v <= b allowed[v] = true v += step end
    end
    return allowed
  end

  def ok(f, v) return f == nil || f.contains(v) end

  # nächster Zeitpunkt (lokale Epoch) > t
  def next(t)
    t += 1
    var guard = 0
    while guard < 200000
      guard += 1
      var d = _emu_time_dump(t)
      if !self.ok(self.f_mon, d['month']) || !self.ok(self.f_dom, d['day']) || !self.ok(self.f_dow, d['weekday'])
        t = (t / 86400 + 1) * 86400
      elif !self.ok(self.f_hour, d['hour'])
        t = (t / 3600 + 1) * 3600
      elif !self.ok(self.f_min, d['min'])
        t = (t / 60 + 1) * 60
      elif !self.ok(self.f_sec, d['sec'])
        t += 1
      else
        return t
      end
    end
    raise "value_error", "Cron-Muster trifft nie zu"
  end
end

# ---------------------------------------------------------------------------
# Zähler-Simulator: liefert JSON wie ein echter gPlug ("z"-Präfix,
# Ei/Eo in kWh, Pi/Po in W — verifiziert an einem gPlugK mit Tasmota 15.3).
# tarife = true: wie ein Zähler mit Tarifregistern (gemessen 02.11.2026 bei
# einem Tester): kein Ei/Eo, sondern Ei1/Ei2, Eo1/Eo2 (Hoch-/Niedertarif,
# OBIS 1.8.1/1.8.2, 2.8.1/2.8.2). Niedertarif hier: 20–7 Uhr.
# ---------------------------------------------------------------------------
class _EmuMeter
  var ei_wh, eo_wh       # Zählerstände in Wh (int, verlustfrei)
  var ei_rest, eo_rest   # Nachkommastellen der Integration
  var pi, po             # aktuelle Leistung in W
  var last_utc
  var enabled            # false = Smart Meter liefert (noch) nichts
  var null_an            # true = alle Werte 0 (Tasmota-SML nach dem Start, noch kein Telegramm)
  var pv_peak            # W bei voller Sonne
  var prefix
  var tarife             # true = Ei1/Ei2, Eo1/Eo2 statt Ei/Eo
  var namen              # Namen der 4 Tarifregister [Ei1, Ei2, Eo1, Eo2]
  var in_wh              # true = Zählerstände in Wh statt kWh
  var ei_nt, eo_nt       # Anteil Niedertarif (Register 2) in Wh

  def init(utc)
    self.ei_wh = 7654321
    self.eo_wh = 234567
    self.ei_rest = 0.0
    self.eo_rest = 0.0
    self.pi = 0
    self.po = 0
    self.last_utc = utc
    self.enabled = true
    self.null_an = false
    self.pv_peak = 6000
    self.prefix = "z"
    self.tarife = false
    self.namen = ["Ei1", "Ei2", "Eo1", "Eo2"]
    self.in_wh = false
    self.ei_nt = 2812345
    self.eo_nt = 81234
  end

  # Netto-Leistung (positiv = Einspeisung) zur lokalen Zeit `loc`
  def net_power(loc)
    var day = loc / 86400
    var h = (loc % 86400) / 3600.0
    var month = _emu_civil(day)[1]
    var summer = 1.0 - math.abs(month - 6.5) / 6.0          # ~0.1 im Winter, ~1 im Sommer
    var rise = 7.5 - 2.0 * summer
    var set = 17.0 + 4.0 * summer
    var pv = 0.0
    if h > rise && h < set
      var cloud = 0.35 + ((day * 37 + 11) % 17) / 25.0     # deterministisch pro Tag
      if cloud > 1.0 cloud = 1.0 end
      pv = self.pv_peak * (0.3 + 0.7 * summer) * cloud * math.sin(math.pi * (h - rise) / (set - rise))
    end
    var load = 280.0
    if h >= 6.5 && h < 8.0 load += 900 end
    if h >= 11.5 && h < 12.5 load += 1800 end
    if h >= 18.0 && h < 21.0 load += 1200 end
    return pv - load
  end

  def advance(utc)
    while self.last_utc < utc
      var step = utc - self.last_utc
      if step > 60 step = 60 end
      var loc = self.last_utc + _emu_tz_offset(self.last_utc) * 60
      var p = self.net_power(loc)
      var wh = (p >= 0 ? p : -p) * step / 3600.0
      var lh = (loc % 86400) / 3600
      var nt = lh < 7 || lh >= 20
      if p >= 0
        self.po = int(p) self.pi = 0
        self.eo_rest += wh
        var w = int(self.eo_rest) self.eo_wh += w self.eo_rest -= w
        if nt self.eo_nt += w end
      else
        self.pi = int(-p) self.po = 0
        self.ei_rest += wh
        var w = int(self.ei_rest) self.ei_wh += w self.ei_rest -= w
        if nt self.ei_nt += w end
      end
      self.last_utc += step
    end
  end

  def kwh(wh) return string.format("%i.%03i", wh / 1000, wh % 1000) end

  # JSON-Fragment ohne äussere Klammern, z.B. "z":{...}
  def json_fragment()
    if !self.enabled return nil end
    if self.null_an
      if self.tarife
        var n = self.namen
        return string.format('"%s":{"SMid":"313233343536","Pi":0.000,"Po":0.000,"%s":0.000,"%s":0.000,"%s":0.000,"%s":0.000}',
                             self.prefix, n[0], n[1], n[2], n[3])
      end
      return string.format('"%s":{"SMid":0,"Pi":0,"Po":0,"Ei":0.000,"Eo":0.000}', self.prefix)
    end
    if self.tarife
      var n = self.namen
      var w = [self.ei_wh - self.ei_nt, self.ei_nt, self.eo_wh - self.eo_nt, self.eo_nt]
      var t = []
      for x: w t.push(self.in_wh ? str(x) : self.kwh(x)) end
      return string.format('"%s":{"SMid":"313233343536","Pi":%.3f,"Po":%.3f,"V1":231.05,"%s":%s,"%s":%s,"%s":%s,"%s":%s}',
                           self.prefix, self.pi / 1000.0, self.po / 1000.0,
                           n[0], t[0], n[1], t[1], n[2], t[2], n[3], t[3])
    end
    return string.format('"%s":{"SMid":12345678,"Pi":%i,"Po":%i,"V1":229,"V2":228,"V3":230,"Ei":%s,"Eo":%s}',
                         self.prefix, self.pi, self.po, self.kwh(self.ei_wh), self.kwh(self.eo_wh))
  end
end

# ---------------------------------------------------------------------------
# BKW-Fixture: erzeugt eine Antwort im Format der echten BKW-API
# (energyreturn, 96 Viertelstunden in UTC) für einen lokalen Tag
# ---------------------------------------------------------------------------
var _EMU_BKW_PROFILE = [   # Rp/kWh je Stunde, Form eines typischen Herbsttages
  23.0, 22.3, 21.8, 21.5, 21.9, 23.1, 26.4, 29.8, 27.2, 22.5, 16.1, 11.3,
  8.9, 8.1, 9.7, 13.8, 19.6, 26.9, 33.5, 35.2, 31.0, 27.4, 25.1, 23.8]

def _emu_iso(utc)
  var t = _emu_time_dump(utc)
  return string.format("%04i-%02i-%02iT%02i:%02i:%02iZ", t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'])
end

def _emu_bkw_fixture(local_day, publish_utc)
  var tz = _emu_tz_offset(local_day * 86400) * 60
  var start = local_day * 86400 - tz
  var s = '{\n  "publication_timestamp": "' + _emu_iso(publish_utc) + '",\n  "prices": ['
  var i = 0
  while i < 96
    var p = _EMU_BKW_PROFILE[i / 4] + ((local_day * 7 + i) % 5 - 2) * 0.4 + ((local_day % 3) - 1) * 1.5
    if i > 0 s += "," end
    s += string.format('\n    {\n      "start_timestamp": "%s",\n      "end_timestamp": "%s",\n      "feed_in": [\n        {\n          "unit": "CHF_kWh",\n          "value": %.4f\n        }\n      ]\n    }',
                       _emu_iso(start + i * 900), _emu_iso(start + i * 900 + 900), p / 100.0)
    i += 1
  end
  return s + "\n  ]\n}"
end

# ---------------------------------------------------------------------------
# Zentrale Emulator-Instanz
# ---------------------------------------------------------------------------
class _Emu
  var utc, frac_ms, boot_utc
  var tz_fixed          # nil = MEZ/MESZ, sonst feste Minuten
  var fs_root
  var app_dir           # Inhalt der .tapp (= build/), erreichbar über tasmota.wd
  var meter
  var fetch_mode        # "fixture" | "proxy" | "error"
  var fetch_count
  var drivers, crons, timers, cmds, routes, rules
  var web_out, web_code, web_mime, req_args
  var resp, cmd_name
  var restart_requested
  var every_second_max
  var exceptions        # Anzahl Exceptions in App-Code (für Tests)
  var uhr_ab            # UTC, ab der die Uhr (NTP) gültig ist; 0 = immer gültig (T.neustart)

  def init()
    self.utc = 1793397600     # 2026-10-30 21:00 MEZ, wird vom Runner überschrieben
    self.frac_ms = 0
    self.boot_utc = self.utc
    self.tz_fixed = nil
    self.fs_root = "fs"
    self.app_dir = "build"
    self.meter = _EmuMeter(self.utc)
    self.fetch_mode = "fixture"
    self.fetch_count = 0
    self.drivers = []
    self.crons = []
    self.timers = []
    self.cmds = {}
    self.routes = []
    self.rules = []
    self.web_out = []
    self.req_args = {}
    self.restart_requested = false
    self.every_second_max = 5
    self.exceptions = 0
    self.uhr_ab = 0
  end

  # App wie eine .tapp laden: app = ".../autoexec.be", Nachbardateien über tasmota.wd
  def load_app(app)
    var sl = size(app) - 1
    while sl >= 0 && app[sl] != "/" sl -= 1 end
    self.app_dir = sl > 0 ? app[0 .. sl - 1] : "."
    print("EMU: Lade " + app + " (tasmota.wd = /gplug.tapp#)")
    global.tasmota.wd = "/gplug.tapp#"
    var ok = true
    try
      compile(app, "file")()
    except .. as e, m
      ok = false
      print(string.format("BRY: failed to load '%s' - %s: %s", app, e, m))
      import debug
      debug.traceback()
    end
    global.tasmota.wd = ""
    return ok
  end

  def set_clock(utc)
    self.utc = utc
    self.boot_utc = utc
    self.frac_ms = 0
    self.meter.last_utc = utc
  end

  def tz() return self.tz_fixed != nil ? self.tz_fixed : _emu_tz_offset(self.utc) end
  def local() return self.utc + self.tz() * 60 end
  def millis() return (self.utc - self.boot_utc) * 1000 + self.frac_ms end

  def fs_path(name)
    name = str(name)
    if string.find(name, "..") >= 0 raise "io_error", "'..' ist nicht erlaubt: " + name end
    while size(name) > 0 && name[0] == "/" name = name[1 ..] end
    var hash = string.find(name, "#")            # Datei in der .tapp: "/gplug.tapp#datei"
    if hash >= 0 return self.app_dir + "/" + name[hash + 1 ..] end
    return self.fs_root + "/" + name
  end

  # --- Ereignisse an Treiber verteilen (wie tasmota_class.be:event) ---
  def dispatch(event, cmd, idx, payload, raw)
    var done = false
    var i = 0
    while i < size(self.drivers)
      var d = self.drivers[i]
      var f = introspect.get(d, event)
      if type(f) == 'function'
        try
          done = f(d, cmd, idx, payload, raw) || done
          if done break end
        except .. as e, m
          self.exceptions += 1
          print(string.format("BRY: Exception> '%s' - %s", e, m))
          import debug
          debug.traceback()
        end
      end
      i += 1
    end
    return done
  end

  def call_safe(f, label)
    try
      f()
    except .. as e, m
      self.exceptions += 1
      print(string.format("BRY: Exception> '%s' - %s (%s)", e, m, label))
      import debug
      debug.traceback()
    end
  end

  # --- Zeit voranschieben: Timer und Cron exakt in zeitlicher Reihenfolge ---
  def advance(ms)
    var t_utc = self.utc + (self.frac_ms + ms) / 1000
    var t_frac = (self.frac_ms + ms) % 1000
    var start_utc = self.utc
    var guard = 0
    while guard < 100000
      guard += 1
      # frühestes fälliges Ereignis suchen
      var best = nil
      var best_s = t_utc
      var best_ms = t_frac
      for tm: self.timers
        if tm[0] < best_s || (tm[0] == best_s && tm[1] <= best_ms)
          best = tm best_s = tm[0] best_ms = tm[1]
        end
      end
      for cr: self.crons
        var cu = cr[0] - self.tz() * 60          # lokale Triggerzeit → UTC
        if cu < best_s || (cu == best_s && best_ms > 0) || (cu == best_s && best == nil)
          best = cr best_s = cu best_ms = 0
        end
      end
      if best == nil break end
      self.utc = best_s
      self.frac_ms = best_ms
      self.meter.advance(self.utc)
      var ti = self.timers.find(best)
      if ti != nil
        self.timers.remove(ti)
        self.call_safe(best[2], "timer")
      else
        best[0] = best[3].next(best[0])
        self.call_safe(best[1], "cron")
      end
    end
    self.utc = t_utc
    self.frac_ms = t_frac
    self.meter.advance(self.utc)
    # every_second: bei Zeitraffer gedrosselt (max. every_second_max Aufrufe pro Schritt)
    var n = self.utc - start_utc
    if n > self.every_second_max n = self.every_second_max end
    while n > 0
      self.dispatch("every_second")
      n -= 1
    end
  end

  # --- Sensoren ---
  def read_sensors()
    var t = _emu_strftime("%Y-%m-%dT%H:%M:%S", self.local())
    var m = self.meter.json_fragment()
    if m == nil return string.format('{"Time":"%s"}', t) end
    return string.format('{"Time":"%s",%s}', t, m)
  end

  # --- HTTP-Ausgang (webclient) ---
  def http_fetch(url, method, payload, headers)
    self.fetch_count += 1
    if self.fetch_mode == "error"
      print("EMU: webclient " + method + " " + url + " -> Netzwerkfehler (simuliert)")
      return [-1, ""]
    end
    if self.fetch_mode == "proxy"
      print("\x02FETCH " + json.dump({'url': url, 'method': method, 'payload': payload, 'headers': headers}))
      var reply = json.load(input())
      var body = ""
      if reply.find('file') != nil
        var f = _emu_fopen(reply['file'], "r")
        body = f.read()
        f.close()
      end
      print("EMU: webclient " + method + " " + url + " -> " + str(reply['code']) + " (" + str(size(body)) + " Byte, live)")
      return [reply['code'], body]
    end
    # fixture: BKW-API simulieren, alles andere 404
    if string.find(url, "api.bkw.ch/api/dyntariffs") >= 0
      var loc = self.local()
      var day = loc / 86400
      if (loc % 86400) >= 18 * 3600 day += 1 end   # Folgetag ab ~18 Uhr publiziert
      var body = _emu_bkw_fixture(day, self.utc)
      print("EMU: webclient " + method + " " + url + " -> 200 (" + str(size(body)) + " Byte, Fixture)")
      return [200, body]
    end
    print("EMU: webclient " + method + " " + url + " -> 404 (Fixture-Modus kennt nur die BKW-API)")
    return [404, ""]
  end

  # --- Kommandos ---
  def exec_cmd(line)
    line = str(line)
    while size(line) > 0 && line[0] == " " line = line[1 ..] end
    var sp = string.find(line, " ")
    var name = sp >= 0 ? line[0 .. sp - 1] : line
    var payload = sp >= 0 ? line[sp + 1 ..] : ""
    var idx = 1
    var up = string.toupper(name)
    var key = up
    if !self.cmds.contains(key)
      # Index-Suffix abtrennen (z.B. "Power2")
      var j = size(up)
      while j > 0 && up[j - 1] >= "0" && up[j - 1] <= "9" j -= 1 end
      if j < size(up) && j > 0 && self.cmds.contains(up[0 .. j - 1])
        idx = int(up[j ..])
        key = up[0 .. j - 1]
      end
    end
    self.resp = nil
    self.cmd_name = name
    if self.cmds.contains(key)
      var pj = nil
      try pj = json.load(payload) except .. end
      if type(pj) != 'instance' pj = nil end
      try
        self.cmds[key](name, idx, payload, pj)
      except .. as e, m
        self.exceptions += 1
        print(string.format("BRY: Exception> '%s' - %s", e, m))
        import debug
        debug.traceback()
        self.resp = string.format('{"%s":"Error"}', name)
      end
      if self.resp == nil self.resp = string.format('{"%s":""}', name) end
      return self.resp
    end
    return self.builtin_cmd(up, name, payload)
  end

  def builtin_cmd(up, name, payload)
    if up == "STATUS"
      var n = payload == "" ? 0 : int(payload)
      if n == 10 || n == 8 return '{"StatusSNS":' + self.read_sensors() + '}' end
      if n == 11
        return string.format('{"StatusSTS":{"Time":"%s","UptimeSec":%i,"Heap":%i,"Berry":{"HeapUsed":%i}}}',
          _emu_strftime("%Y-%m-%dT%H:%M:%S", self.local()), self.utc - self.boot_utc, 105, gc.allocated() / 1024)
      end
      if n == 7
        return string.format('{"StatusTIM":{"UTC":"%s","Local":"%s","Timezone":99}}',
          _emu_iso(self.utc), _emu_strftime("%Y-%m-%dT%H:%M:%S", self.local()))
      end
      return '{"Status":{"DeviceName":"gPlug-Emulator","FriendlyName":["gPlug"],"Topic":"gplug"}}'
    elif up == "TIME"
      return '{"Time":"' + _emu_strftime("%Y-%m-%dT%H:%M:%S", self.local()) + '"}'
    elif up == "RESTART"
      self.restart_requested = true
      return '{"Restart":"Restarting"}'
    elif up == "BR"
      var r
      try
        var f
        try f = compile("return " + payload) except "syntax_error" f = compile(payload) end
        r = f()
      except .. as e, m
        return json.dump({'Br': '[' + str(e) + '] ' + str(m)})
      end
      return json.dump({'Br': str(r)})
    end
    return '{"Command":"Unknown","Input":"' + name + '"}'
  end
end

var _emu = _Emu()

# ---------------------------------------------------------------------------
# Globale Funktion log() und das Objekt `tasmota`
# ---------------------------------------------------------------------------
def log(msg, level)
  if level == nil level = 2 end
  var lv = ["NONE", "ERR", "INF", "DBG", "DBGM"]
  print(string.format("%s %s: %s", _emu_strftime("%H:%M:%S", _emu.local()), lv[level < 5 ? level : 4], str(msg)))
end

class _EmuTasmota
  var wd
  var _debug_present

  def init() self.wd = "" end

  def check_not_method(f)
    if type(f) != 'function' raise "type_error", "Funktion/Closure erwartet" end
    import introspect
    if introspect.ismethod(f) == true
      raise "type_error", "Methoden sind nicht erlaubt, Closure verwenden: /-> self.methode()"
    end
  end

  # Treiber
  def add_driver(d)
    if type(d) != 'instance' raise "value_error", "instance required" end
    if _emu.drivers.find(d) == nil _emu.drivers.push(d) end
  end
  def remove_driver(d)
    var i = _emu.drivers.find(d)
    if i != nil _emu.drivers.remove(i) end
  end

  # Zeit
  def rtc(key)
    var m = {'utc': _emu.utc, 'local': _emu.local(), 'timezone': _emu.tz(), 'restart': _emu.boot_utc}
    if _emu.utc < _emu.uhr_ab         # vor NTP (T.neustart): Sekunden seit dem Start, wie auf dem Gerät
      var s = _emu.utc - _emu.boot_utc
      m = {'utc': s, 'local': s, 'timezone': _emu.tz(), 'restart': 0}
    end
    return key != nil ? m.find(key) : m
  end
  def time_dump(ts) return _emu_time_dump(int(ts)) end
  def strftime(fmt, ts) return _emu_strftime(fmt, int(ts)) end
  def time_str(ts) return _emu_strftime("%Y-%m-%dT%H:%M:%S", int(ts)) end
  def millis(d) return _emu.millis() + (d != nil ? d : 0) end
  def time_reached(t) return _emu.millis() >= t end
  def strptime(s, fmt)
    # nur "%Y-%m-%dT%H:%M:%S" (und Varianten mit Leerzeichen) — wie auf dem Gerät: epoch ohne Zeitzone
    if size(s) < 19 return nil end
    var y = int(s[0..3]) var mo = int(s[5..6]) var d = int(s[8..9])
    var h = int(s[11..12]) var mi = int(s[14..15]) var se = int(s[17..18])
    var ep = _emu_days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + se
    var r = _emu_time_dump(ep)
    r['unparsed'] = s[19 ..]
    return r
  end

  # Timer und Cron
  def set_timer(ms, f, id)
    self.check_not_method(f)
    var tot = _emu.frac_ms + ms
    _emu.timers.push([_emu.utc + tot / 1000, tot % 1000, f, id])
  end
  def remove_timer(id)
    var i = 0
    while i < size(_emu.timers)
      if _emu.timers[i][3] == id _emu.timers.remove(i) else i += 1 end
    end
  end
  def add_cron(pattern, f, id)
    self.check_not_method(f)
    var c = _EmuCron(str(pattern))
    _emu.crons.push([c.next(_emu.local()), f, id, c])
  end
  def remove_cron(id)
    var i = 0
    while i < size(_emu.crons)
      if _emu.crons[i][2] == id _emu.crons.remove(i) else i += 1 end
    end
  end
  def next_cron(id)
    for c: _emu.crons if c[2] == id return c[0] end end
    return nil
  end
  def defer(f) self.set_timer(0, f) end
  def yield() end
  def delay(ms) end

  # Netzwerk
  def is_network_up() return true end
  def when_network_up(f) self.set_timer(0, f) end
  def wifi(key)
    var m = {'up': true, 'ip': '127.0.0.1', 'rssi': -60, 'quality': 80, 'mac': 'AA:BB:CC:DD:EE:FF'}
    return key != nil ? m.find(key) : m
  end
  def eth(key) var m = {'up': false} return key != nil ? m.find(key) : m end

  # Sensoren, Log, Speicher
  def read_sensors(show) return _emu.read_sensors() end
  def log(msg, level) log(msg, level) end
  def memory(key)
    var used = gc.allocated()
    # Schätzung für einen gPlug (ESP32-C3): Desktop-Objekte sind ~1.6× grösser
    var m = {'heap_free': 150 - used * 10 / 16 / 1024, 'gc_heap': used * 10 / 16 / 1024, 'frag': 30, 'flash': 4096, 'program': 2147}
    return key != nil ? m.find(key) : m
  end
  def gc() gc.collect() return gc.allocated() end
  def get_free_heap() return 105000 - gc.allocated() / 2 end

  # Web-Ausgabe aus web_sensor()
  def web_send(s) _emu.web_out.push(str(s)) end
  def web_send_decimal(s) _emu.web_out.push(str(s)) end
  def response_append(s) end

  # Kommandos
  def add_cmd(name, f)
    self.check_not_method(f)
    _emu.cmds[string.toupper(name)] = f
  end
  def remove_cmd(name) _emu.cmds.remove(string.toupper(name)) end
  def resp_cmnd(s) _emu.resp = s end
  def resp_cmnd_str(s) _emu.resp = json.dump({_emu.cmd_name: s}) end
  def resp_cmnd_done() self.resp_cmnd_str("Done") end
  def resp_cmnd_error() self.resp_cmnd_str("Error") end
  def resp_cmnd_failed() self.resp_cmnd_str("Fail") end
  def cmd(c, mute)
    var r = _emu.exec_cmd(c)
    try return json.load(r) except .. return r end
  end

  # Regeln: werden gespeichert, im Emulator aber nicht ausgelöst
  def add_rule(trigger, f, id) _emu.rules.push([trigger, f, id]) end
  def remove_rule(trigger, id) end

  def get_power(i) return [false] end
  def set_power(i, v) return v end
  def publish(topic, payload) print("EMU: MQTT publish " + str(topic) + " " + str(payload)) end
  def urlfetch(url, file) raise "not_implemented_error", "tasmota.urlfetch im Emulator nicht verfügbar — webclient verwenden" end
end

var tasmota = _EmuTasmota()

# ---------------------------------------------------------------------------
# webclient (globale Klasse auf dem Gerät)
# ---------------------------------------------------------------------------
class webclient
  var url, headers, code, body

  def init() self.headers = {} self.code = 0 end
  def begin(url) self.url = str(url) self.body = nil return self end
  def set_timeouts(a, b) return self end
  def set_useragent(u) return self end
  def set_follow_redirects(b) return self end
  def set_auth(a, b) return self end
  def collect_headers() return self end
  def get_header(h) return nil end
  def add_header(k, v, first, replace) self.headers[k] = v end
  def addheader(k, v) self.add_header(k, v) end
  def connected() return false end
  def _req(method, payload)
    if self.url == nil raise "value_error", "webclient: zuerst begin(url) aufrufen" end
    var r = _emu.http_fetch(self.url, method, payload, self.headers)
    self.code = r[0]
    self.body = r[1]
    return self.code
  end
  def GET() return self._req("GET", nil) end
  def POST(p) return self._req("POST", str(p)) end
  def PUT(p) return self._req("PUT", str(p)) end
  def DELETE() return self._req("DELETE", nil) end
  def get_string()
    if self.body != nil && size(self.body) > 8192
      print(string.format("EMU-WARNUNG: webclient.get_string() mit %i Byte — auf dem gPlug (ESP32-C3) kann das bei wenig freiem Heap unvollständig ankommen oder einen Neustart auslösen. Besser: write_file() und stückweise lesen.", size(self.body)))
    end
    return self.body != nil ? self.body : ""
  end
  def get_size() return self.body != nil ? size(self.body) : -1 end
  def get_bytes() return bytes().fromstring(self.get_string()) end
  def write_file(name)
    var body = self.body != nil ? self.body : ""
    var f = _emu_fopen(_emu.fs_path(name), "w")
    f.write(body)
    f.close()
    return size(body)
  end
  def close() self.body = nil end
  static def url_encode(s) return s end
end

# ---------------------------------------------------------------------------
# open(): Gerätepfade ("/datei.csv") auf das Emulator-Dateisystem abbilden
# ---------------------------------------------------------------------------
global.open = def (name, mode)
  if mode == nil mode = "r" end
  return _emu_fopen(_emu.fs_path(name), mode)
end

# load(): auf dem Gerät eingebaut (tasmota_class.be), lädt und startet eine .be-Datei
global.load = def (name)
  try
    compile(str(name), "file")()
    return true
  except .. as e, m
    print(string.format("BRY: failed to load '%s' - %s: %s", name, e, m))
    return false
  end
end

# Wie auf dem Gerät: Tasmota übersetzt Apps im strict-Modus. Eine Zuweisung an einen
# nicht deklarierten Namen in einer Funktion (`l = []` statt `var l = []`) ist dort ein
# syntax_error ("strict: no global 'l', did you mean 'var l'?") und die .tapp lädt nicht.
# Gilt für alles, was nach diesem Punkt kompiliert wird (App, Tests, Br-Befehle).
import strict
