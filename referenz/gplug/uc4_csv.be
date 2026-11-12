# uc4_csv.be — Tagesabrechnung als CSV pro Monat (UC4)
#
# 00:01: Zeile für gestern (Index 0–95) an /gplug_JJJJ-MM.csv anhängen; jeder Tag genau
# einmal (persist.gplug_csv_tag), verpasster Abschluss wird beim Start nachgeholt.
# Heap: eine Zeile Text; die Datei wird nur ergänzt.

var UC4_KOPF = "Datum;Einspeisung_kWh;Verguetung_CHF;Bezug_kWh;Luecken_h\n"

def uc4_kwh(wh) return string.format("%i.%03i", wh / 1000, wh % 1000) end

# Skill tasmota-berry: "gplug_2026-09.csv" → 2026 * 12 + 9; sonst nil
def uc4_monat(name)
  if size(name) != 17 || name[0 .. 5] != "gplug_" || name[13 ..] != ".csv" return nil end
  return int(name[6 .. 9]) * 12 + int(name[11 .. 12])
end

# höchstens csv_monate Dateien: ältere als (Monat − csv_monate + 1) löschen
def uc4_aufraeumen(jahr, monat)
  import path
  var grenze = jahr * 12 + monat - int(gplug_cfg.find("csv_monate", 3))
  for n: path.listdir("/")
    var m = uc4_monat(n)
    if m != nil && m <= grenze
      path.remove("/" + n)
      log("GPL: UC4 alte Datei gelöscht: " + n, 2)
    end
  end
end

def uc4_abschluss()
  if !gplug_tag_pruefen() return end
  import persist
  import path
  var tag = gplug_tag0                          # gestern
  if persist.find("gplug_csv_tag", 0) >= tag return end
  if gplug_anzahl(gplug_e, 0, 95) == 0 && gplug_anzahl(gplug_b, 0, 95) == 0 return end   # keine Messwerte
  var luecken = 0
  for i: 0 .. 95
    if gplug_wert(gplug_e, i) == nil || gplug_wert(gplug_p, i) == nil luecken += 1 end
  end
  var d = tasmota.time_dump(tag * 86400)
  var name = string.format("/gplug_%04i-%02i.csv", d["year"], d["month"])
  try
    var neu = !path.exists(name)
    var f = open(name, "a")
    if neu f.write(UC4_KOPF) end
    f.write(string.format("%04i-%02i-%02i;%s;%.2f;%s;%.2f\n", d["year"], d["month"], d["day"],
      uc4_kwh(gplug_summe(gplug_e, 0, 95)), gplug_verguetung(0, 95),
      uc4_kwh(gplug_summe(gplug_b, 0, 95)), luecken / 4.0))
    f.close()
  except .. as e, m
    log("GPL: UC4 " + name + ": " + str(m), 2)
    return
  end
  persist.gplug_csv_tag = tag
  persist.save()
  uc4_aufraeumen(d["year"], d["month"])
end
