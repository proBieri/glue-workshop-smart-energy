# uc1_preise.be — Einspeisetarife der BKW abrufen (UC1)
#
# Antwort (~21 kB) mit write_file() in eine Datei, in 1-kB-Stücken lesen (kein json.load,
# kein get_string — beides auf dem gPlug gescheitert). Heap beim Abruf: ~2 kB Text plus
# eine Kopie des Tarifpuffers (576 B), danach frei.

var UC1_URL = "https://api.bkw.ch/api/dyntariffs/v1/Tariffs/energyreturn"
var UC1_TMP = "/gplug_bkw.tmp"
var UC1_DATEI = "/gplug_preise.json"
var uc1_letzter = nil              # Zeit des letzten erfolgreichen Abrufs
var uc1_fehler = 0                 # Fehler seit dem Start

# Skill tasmota-berry „Einträge mit mehreren Feldern stückweise lesen“ — unverändert
def uc1_eintraege(name, fn)
  import string
  var f = open(name, "r")
  var rest = ""
  var n = 0
  while true
    var teil = f.read(1024)
    var s = rest + teil
    var pos = 0
    var offen = -1
    while true
      var i = string.find(s, '"start_timestamp"', pos)
      if i < 0 break end
      var q = string.find(s, '"', i + 17)
      var z = q < 0 ? -1 : string.find(s, '"', q + 1)
      var v = z < 0 ? -1 : string.find(s, '"value"', z)
      var a = v < 0 ? -1 : string.find(s, ":", v)
      var b = a < 0 ? -1 : a + 1
      while b >= 0 && b < size(s) && s[b] == " " b += 1 end
      var e = b
      while e >= 0 && e < size(s) && string.find(",}] \n\r", s[e]) < 0 e += 1 end
      if e < 0 || e >= size(s) offen = i break end
      fn(s[q + 1 .. z - 1], real(s[b .. e - 1]))
      n += 1
      pos = e
    end
    if offen >= 0
      rest = s[offen ..]
    else
      var k = size(s) - 16
      if k < pos k = pos end
      rest = k < size(s) ? s[k ..] : ""
    end
    if size(teil) == 0 break end
  end
  f.close()
  return n
end

def uc1_speichern()
  if gplug_tag0 == 0 return end
  gplug_json_schreiben(UC1_DATEI, {"t0": gplug_tag0, "p": gplug_p.tob64()})
end

# gespeicherte Tarife laden; liefert den Tag von Index 0 der Datei (0 = keine)
def uc1_laden()
  var m = gplug_json_lesen(UC1_DATEI)
  if m == nil return 0 end
  var b = bytes().fromb64(m.find("p", ""))
  if size(b) != 576 return 0 end
  gplug_p = b
  return int(m.find("t0", 0))
end

# Fehlen Tarife? Vor 18 Uhr die von heute, ab 18 Uhr die von morgen (früher gibt es sie nicht,
# danach liefert die API nur noch morgen)
def uc1_noetig()
  if (gplug_jetzt() % 86400) / 3600 < 18 return gplug_anzahl(gplug_p, 96, 191) < 96 end
  return gplug_anzahl(gplug_p, 192, 287) < 96
end

# Antwortdatei in eine Kopie des Puffers einlesen; erst bei ≥ 96 Viertelstunden übernehmen
def uc1_einlesen()
  var neu = bytes() + gplug_p
  var tz = gplug_tz()
  var basis = gplug_tag0 * 96
  var n = 0
  uc1_eintraege(UC1_TMP, def (zeit, wert)
    var t = tasmota.strptime(zeit, "%Y-%m-%dT%H:%M:%SZ")
    if t == nil return end
    var i = (t["epoch"] + tz) / 900 - basis
    if i < 0 || i > 287 return end
    var v = wert * 10000
    gplug_setzen(neu, i, int(v >= 0 ? v + 0.5 : v - 0.5))
    n += 1
  end)
  if n < 96
    log("GPL: UC1 nur " + str(n) + " Viertelstunden in der Antwort", 2)
    return false
  end
  gplug_p = neu
  return true
end

def uc1_abruf()
  if !gplug_tag_pruefen() return false end
  import path
  var ok = false
  try
    var cl = webclient()
    cl.begin(UC1_URL)
    var code = cl.GET()
    var n = 0
    if code == 200 n = cl.write_file(UC1_TMP) end
    cl.close()
    if code == 200 && n > 0
      ok = uc1_einlesen()
    else
      log("GPL: UC1 BKW-Abruf fehlgeschlagen, HTTP " + str(code), 2)
    end
  except .. as e, m
    log("GPL: UC1 Abruf: " + str(e) + " " + str(m), 2)
  end
  if path.exists(UC1_TMP) path.remove(UC1_TMP) end
  if ok
    uc1_letzter = tasmota.time_str(gplug_jetzt())
    uc1_speichern()
    log("GPL: UC1 Tarife: heute " + str(gplug_anzahl(gplug_p, 96, 191)) + ", morgen " + str(gplug_anzahl(gplug_p, 192, 287)), 2)
  else
    uc1_fehler += 1
  end
  return ok
end
