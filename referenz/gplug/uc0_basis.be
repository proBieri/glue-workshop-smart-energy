# uc0_basis.be — gemeinsame Helfer: Konfiguration, Zeit, Tagespuffer
#
# Drei Puffer à 3 Tage × 96 Viertelstunden × int16 (576 Byte), Index 0 = gestern 00:00,
# 0x8000 = leer: Tarif (0.01 Rp/kWh, UC1), Einspeisung und Bezug (Wh, UC2).
# Heap: fix ~1.8 kB für die Puffer.

import string
import json

var GPLUG_WD = tasmota.wd          # nur beim Laden der .tapp gesetzt (Skill)
var GPLUG_VERSION = "2.0"
var GPLUG_LEER = 0x8000

def gplug_puffer()
  var b = bytes(-576)
  for i: 0 .. 287 b.set(i * 2, GPLUG_LEER, 2) end
  return b
end

var gplug_p = gplug_puffer()       # Tarif in 0.01 Rp/kWh
var gplug_e = gplug_puffer()       # Einspeisung in Wh
var gplug_b = gplug_puffer()       # Bezug in Wh
var gplug_tag0 = 0                 # Tag (seit 1970, lokal) von Index 0; 0 = unbekannt
var gplug_cfg = {}                 # /gplug.json

def gplug_zeit_ok() return tasmota.rtc()["utc"] > 1700000000 end
def gplug_jetzt() return tasmota.rtc()["local"] end
def gplug_tz() var r = tasmota.rtc() return r["local"] - r["utc"] end

# Index der Viertelstunde, in der die lokale Epoch t liegt
def gplug_index(t) return t / 900 - gplug_tag0 * 96 end

def gplug_wert(b, i)
  if i < 0 || i > 287 return nil end
  var v = b.get(i * 2, 2)
  if v == GPLUG_LEER return nil end
  return v >= 32768 ? v - 65536 : v
end

def gplug_setzen(b, i, v)
  if i < 0 || i > 287 return end
  if v == nil b.set(i * 2, GPLUG_LEER, 2) return end      # Leer-Marker direkt schreiben
  if v > 32767 v = 32767 elif v < -32767 v = -32767 end
  b.set(i * 2, v & 0xFFFF, 2)
end

def gplug_anzahl(b, von, bis)
  var n = 0
  for i: von .. bis if b.get(i * 2, 2) != GPLUG_LEER n += 1 end end
  return n
end

def gplug_summe(b, von, bis)
  var s = 0
  for i: von .. bis
    var v = gplug_wert(b, i)
    if v != nil s += v end
  end
  return s
end

# Vergütung in CHF: Σ Einspeisung (Wh) × Tarif (0.01 Rp/kWh) = e/1000 kWh × p/10000 CHF/kWh
def gplug_verguetung(von, bis)
  var chf = 0.0
  for i: von .. bis
    var e = gplug_wert(gplug_e, i)
    var p = gplug_wert(gplug_p, i)
    if e != nil && p != nil chf += real(e) * p / 10000000.0 end
  end
  return chf
end

# Puffer um d Tage (1 oder 2) nach vorne schieben: gestern fällt weg, morgen wird leer
def gplug_schieben(b, d)
  var n = gplug_puffer()
  for i: 0 .. 287 - d * 96 n.set(i * 2, b.get((i + d * 96) * 2, 2), 2) end
  return n
end

# Puffer, der zum Tag t gehört, auf gplug_tag0 ausrichten (nach dem Laden aus einer Datei)
def gplug_angleichen(b, t)
  var d = gplug_tag0 - t
  if d == 0 return b end
  if t == 0 || d < 0 || d > 2 return gplug_puffer() end
  return gplug_schieben(b, d)
end

# Vor jeder Verwendung der Puffer: neuer Tag → schieben. Erst mit gültiger Uhr — beim
# Start vor NTP ist local ~0 und würde die eben geladenen Daten löschen.
def gplug_tag_pruefen()
  if !gplug_zeit_ok() return false end
  var soll = gplug_jetzt() / 86400 - 1
  if soll == gplug_tag0 return true end
  var d = soll - gplug_tag0
  if gplug_tag0 == 0 || d < 0 || d > 2
    gplug_p = gplug_puffer()
    gplug_e = gplug_puffer()
    gplug_b = gplug_puffer()
  else
    gplug_p = gplug_schieben(gplug_p, d)
    gplug_e = gplug_schieben(gplug_e, d)
    gplug_b = gplug_schieben(gplug_b, d)
  end
  gplug_tag0 = soll
  return true
end

def gplug_json_lesen(name)
  try
    var f = open(name, "r")
    var m = json.load(f.read())
    f.close()
    return isinstance(m, map) ? m : nil
  except ..
    return nil
  end
end

def gplug_json_schreiben(name, m)
  try
    var f = open(name, "w")
    f.write(json.dump(m))
    f.close()
  except .. as e, t
    log("GPL: " + name + " nicht geschrieben: " + str(t), 2)
  end
end

def gplug_cfg_laden()
  var m = gplug_json_lesen("/gplug.json")
  if m != nil gplug_cfg = m end
end
