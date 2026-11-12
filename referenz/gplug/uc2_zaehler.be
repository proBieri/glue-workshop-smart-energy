# uc2_zaehler.be — Einspeisung und Bezug pro Viertelstunde (UC2)
#
# Viertelstunde (:00/:15/:30/:45): Differenz zur Basis → eben beendete Viertelstunde,
# neue Basis. Jede Minute: laufende Viertelstunde = Stand − Basis. Die Basis gilt nur für
# die Viertelstunde, an deren Anfang sie gelesen wurde (±60 s) — nach einem Ausfall oder
# Start mitten in der Viertelstunde wird nichts über mehrere Viertelstunden verteilt.
# Heap: Puffer in uc0; Speicher-Datei ~1.7 kB, jede Viertelstunde geschrieben.

var UC2_DATEI = "/gplug_zaehler.json"
var uc2_letzt = [nil, nil]         # letzter Stand in Wh (0 = Einspeisung, 1 = Bezug)
var uc2_basis = [nil, nil]         # Stand am Anfang der laufenden Viertelstunde
var uc2_bzeit = [0, 0]             # Zeit der Basis (lokal)

def uc2_puffer(k) return k == 0 ? gplug_e : gplug_b end

def uc2_gilt(k, q0) return uc2_basis[k] != nil && uc2_bzeit[k] >= q0 - 60 && uc2_bzeit[k] <= q0 + 60 end

var UC2_MAX = 20000                # Wh pro Viertelstunde (80 kW); mehr = Messfehler

# Stand 0, obwohl schon ein Stand > 0 bekannt ist: Tasmota-SML hat nach dem Start noch
# kein Telegramm dekodiert (Wattenwil 11.11.2026: 0 als Basis → 32767 Wh um 00:00) → nil
def uc2_lesen()
  var s = tasmota.read_sensors()
  if s == nil return [nil, nil] end
  var r = [uc2_stand(s, uc2_ein, "Eo"), uc2_stand(s, uc2_bez, "Ei")]
  for k: 0 .. 1
    var alt = uc2_letzt[k] != nil ? uc2_letzt[k] : uc2_basis[k]
    if r[k] == 0 && alt != nil && alt > 0 r[k] = nil end
  end
  return r
end

# Energie seit der Basis, oder nil (gesunken = Zählertausch, zu gross = Messfehler)
def uc2_diff(k, v)
  var d = v - uc2_basis[k]
  return (d >= 0 && d <= UC2_MAX) ? d : nil
end

def uc2_speichern()
  if gplug_tag0 == 0 return end
  gplug_json_schreiben(UC2_DATEI, {"t0": gplug_tag0, "e": gplug_e.tob64(), "b": gplug_b.tob64(),
    "basis": uc2_basis, "bzeit": uc2_bzeit})
end

# gespeicherte Werte laden; liefert den Tag von Index 0 der Datei (0 = keine)
def uc2_laden()
  var m = gplug_json_lesen(UC2_DATEI)
  if m == nil return 0 end
  var e = bytes().fromb64(m.find("e", ""))
  var b = bytes().fromb64(m.find("b", ""))
  if size(e) != 576 || size(b) != 576 return 0 end
  for i: 0 .. 287                               # Messfehler älterer Versionen (32767) verwerfen
    var w = gplug_wert(e, i) if w != nil && w > UC2_MAX gplug_setzen(e, i, nil) end
    w = gplug_wert(b, i) if w != nil && w > UC2_MAX gplug_setzen(b, i, nil) end
  end
  gplug_e = e
  gplug_b = b
  var ba = m.find("basis")
  var bz = m.find("bzeit")
  if isinstance(ba, list) && isinstance(bz, list) && size(ba) == 2 && size(bz) == 2
    uc2_basis = ba
    uc2_bzeit = [int(bz[0]), int(bz[1])]
  end
  return int(m.find("t0", 0))
end

# 20 s nach dem Start: Schlüssel festlegen, Basis setzen (eine gespeicherte Basis der
# laufenden Viertelstunde gilt weiter) — keine Viertelstunde schreiben
def uc2_start()
  uc2_schluessel()
  if !gplug_tag_pruefen() return end
  var t = gplug_jetzt()
  var q0 = (t / 900) * 900
  var r = uc2_lesen()
  for k: 0 .. 1
    uc2_letzt[k] = r[k]
    if r[k] != nil && !(uc2_gilt(k, q0) && r[k] >= uc2_basis[k])
      uc2_basis[k] = r[k]
      uc2_bzeit[k] = t
    end
  end
end

# Cron zur Viertelstunde
def uc2_viertelstunde()
  if !uc2_bereit || !gplug_tag_pruefen() return end
  var q0 = (gplug_jetzt() / 900) * 900          # Anfang der neuen Viertelstunde
  var r = uc2_lesen()
  for k: 0 .. 1
    var b = uc2_puffer(k)
    var i = gplug_index(q0 - 900)               # eben beendete Viertelstunde
    var v = r[k]
    if v == nil
      gplug_setzen(b, i, nil)                   # kein Endstand → nicht vollständig, leer (UC2-3)
    else
      if uc2_gilt(k, q0 - 900)
        gplug_setzen(b, i, uc2_diff(k, v))
      end
      uc2_letzt[k] = v
      uc2_basis[k] = v
      uc2_bzeit[k] = q0
      gplug_setzen(b, gplug_index(q0), 0)       # laufende Viertelstunde beginnt bei 0
    end
  end
  uc2_speichern()
end

# Cron jede Minute: laufende Viertelstunde
def uc2_minute()
  if !uc2_bereit || !gplug_tag_pruefen() return end
  var t = gplug_jetzt()
  var q0 = (t / 900) * 900
  var r = uc2_lesen()
  for k: 0 .. 1
    if r[k] != nil
      uc2_letzt[k] = r[k]
      var d = uc2_gilt(k, q0) ? uc2_diff(k, r[k]) : nil
      if d != nil gplug_setzen(uc2_puffer(k), gplug_index(t), d) end
    end
  end
end
