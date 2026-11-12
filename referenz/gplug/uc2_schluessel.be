# uc2_schluessel.be — welche Zählerschlüssel und welche Einheit? (UC2 Konfiguration und Namenssuche, UC5 Skript; 20 s nach dem Start)
#
# 1. /gplug.json key_ein/key_bez/einheit (nur wenn wirklich eingetragen)
# 2. SML-Skript /script.txt, Abschnitt >M: OBIS C.8.E (C=1 Bezug, C=2 Einspeisung)
# 3. Namenssuche: Eo bzw. Ei, sonst die Summe Eo1 + Eo2 …
# Heap: zwei kleine Maps; das Skript wird zeilenweise gelesen.

var uc2_ein = nil                  # {"k": [Schlüssel], "wh": Einheit Wh?}; nil = Namenssuche
var uc2_bez = nil
var uc2_quelle = "Namenssuche"
var uc2_bereit = false

# Zahl aus dem Text in Wh, ohne float (32 Bit): "234.567" kWh → 234567, "23456789" Wh → 23456789
def uc2_wh_text(t, wh)
  var p = string.find(t, ".")
  var ganz = p < 0 ? t : (p == 0 ? "0" : t[0 .. p - 1])
  var rest = p < 0 ? "" : t[p + 1 ..]
  if wh return int(ganz) + ((size(rest) > 0 && rest[0] >= "5") ? 1 : 0) end
  return int(ganz) * 1000 + int((rest + "000")[0 .. 2])
end

# Wert zum Schlüssel aus dem Status-10-Text in Wh, oder nil
def uc2_wert(s, key, wh)
  var m = '"' + key + '":'
  var i = string.find(s, m)
  if i < 0 return nil end
  var a = i + size(m)
  var e = a
  while e < size(s) && string.find(",}] ", s[e]) < 0 e += 1 end
  if e == a || s[a] == '"' || s[a] == "n" return nil end
  return uc2_wh_text(s[a .. e - 1], wh)
end

# Stand einer Richtung in Wh: feste Schlüssel (Summe) oder Namenssuche mit Präfix
def uc2_stand(s, cfg, praefix)
  if cfg != nil
    var sum = 0
    for k: cfg["k"]
      var v = uc2_wert(s, k, cfg["wh"])
      if v == nil return nil end
      sum += v
    end
    return sum
  end
  var v = uc2_wert(s, praefix, false)
  if v != nil return v end
  var sum = nil
  for n: 1 .. 9
    var w = uc2_wert(s, praefix + str(n), false)
    if w == nil break end
    sum = (sum == nil ? 0 : sum) + w
  end
  return sum
end

# eine >M-Zeile → [C, D, E, JSON-Name, Einheit] oder nil
def uc2_skript_zeile(z)
  var c = -1, d = -1, e = -1
  var i = string.find(z, "1-0:")
  if i >= 0
    var j = string.find(z, "(", i)
    if j < 0 return nil end
    var t = string.split(z[i + 4 .. j - 1], ".")
    if size(t) < 3 return nil end
    c = int(t[0]) d = int(t[1]) e = int(t[2])
  else
    i = string.find(z, "77070100")         # SML binär: 77070100 CC DD EE ff
    if i < 0 || i + 13 >= size(z) return nil end
    var h = bytes(z[i + 8 .. i + 13])
    c = h[0] d = h[1] e = h[2]
  end
  var k = string.find(z, "(@")
  if k < 0 return nil end
  var f = string.split(z[k + 2 ..], ",")   # Teiler, Text, Einheit, JSON-Name, Stellen
  if size(f) < 4 return nil end
  return [c, d, e, string.tr(f[3], " ", ""), string.tr(f[2], " ", "")]
end

# aus den Energiezeilen einer Richtung: Gesamtstand (E = 0) oder alle Tarifregister
def uc2_wahl(l)
  if size(l) == 0 return nil end
  var k = []
  for r: l if r[2] == 0 k = [r[3]] end end
  if size(k) == 0 for r: l k.push(r[3]) end end
  return {"k": k, "wh": l[0][4] == "Wh"}
end

def uc2_skript()
  var f
  try f = open("/script.txt", "r") except .. return false end
  var ein = []
  var bez = []
  var im_m = false
  while true
    var z = f.readline()
    if size(z) == 0 break end
    z = string.tr(z, "\r\n", "")
    if size(z) > 0 && z[0] == ">" im_m = string.startswith(z, ">M") continue end
    if !im_m || size(z) == 0 || z[0] == ";" continue end
    var r = uc2_skript_zeile(z)
    if r == nil || r[1] != 8 continue end
    if r[0] == 2 ein.push(r) elif r[0] == 1 bez.push(r) end
  end
  f.close()
  if size(ein) == 0 && size(bez) == 0 return false end
  uc2_ein = uc2_wahl(ein)
  uc2_bez = uc2_wahl(bez)
  uc2_quelle = "script.txt"
  return true
end

def uc2_name(cfg, praefix)
  if cfg == nil return praefix end
  return cfg["k"].concat("+") + (cfg["wh"] ? " Wh" : " kWh")
end

def uc2_beschreibung()
  return uc2_quelle + ": " + uc2_name(uc2_ein, "Eo") + " / " + uc2_name(uc2_bez, "Ei")
end

def uc2_schluessel()
  var ke = gplug_cfg.find("key_ein")
  var kb = gplug_cfg.find("key_bez")
  if ke != nil || kb != nil
    var wh = gplug_cfg.find("einheit", "kWh") == "Wh"   # "Eo1+Eo2" = Summe der Register
    if ke != nil uc2_ein = {"k": string.split(str(ke), "+"), "wh": wh} end
    if kb != nil uc2_bez = {"k": string.split(str(kb), "+"), "wh": wh} end
    uc2_quelle = "gplug.json"
  else
    uc2_skript()
  end
  uc2_bereit = true
  log("GPL: UC2 Zähler: " + uc2_beschreibung(), 2)
end
