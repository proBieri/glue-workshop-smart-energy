# uc6_befehle.be — Tasmota-Befehle GplugInfo, GplugPreise, GplugAbruf (UC6)
#
# Konsole, HTTP (/cm?cmnd=…) und MQTT; Gross-/Kleinschreibung erledigt Tasmota.
# Heap: nur die Antwort (< 1 kB) während des Befehls.

def uc6_info(cmd, idx, payload, pj)
  gplug_tag_pruefen()
  tasmota.resp_cmnd(json.dump({"GplugInfo": {
    "Version": GPLUG_VERSION,
    "Zeit": tasmota.time_str(gplug_jetzt()),
    "Preise_heute": gplug_anzahl(gplug_p, 96, 191),
    "Preise_morgen": gplug_anzahl(gplug_p, 192, 287),
    "Letzter_Abruf": uc1_letzter,
    "Abruf_Fehler": uc1_fehler,
    "Viertelstunden_heute": gplug_anzahl(gplug_e, 96, 191),
    "Zaehler_Eo_Wh": uc2_letzt[0],
    "Zaehler_Ei_Wh": uc2_letzt[1],
    "Zaehler": uc2_beschreibung(),
    "Heap_kB": tasmota.memory()["heap_free"]}}))
end

# Tarife der nächsten 12 Viertelstunden ab der laufenden, in Rp/kWh
def uc6_preise(cmd, idx, payload, pj)
  gplug_tag_pruefen()
  var t = gplug_jetzt()
  var i = gplug_index(t)
  var l = []
  for k: 0 .. 11
    var p = gplug_wert(gplug_p, i + k)
    l.push(p == nil ? nil : p / 100.0)
  end
  tasmota.resp_cmnd(json.dump({"GplugPreise": {"ab": tasmota.time_str((t / 900) * 900), "rp_kwh": l}}))
end

def uc6_abruf(cmd, idx, payload, pj)
  tasmota.resp_cmnd(uc1_abruf() ? '{"GplugAbruf":"Done"}' : '{"GplugAbruf":"Fail"}')
end

tasmota.add_cmd("GplugInfo", uc6_info)
tasmota.add_cmd("GplugPreise", uc6_preise)
tasmota.add_cmd("GplugAbruf", uc6_abruf)
