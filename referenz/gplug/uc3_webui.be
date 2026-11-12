# uc3_webui.be — Momentanwerte und 3-Tage-Grafik im WebUI (UC3)
#
# Hauptseite: gplug_ui.html aus der .tapp, in 2-kB-Stücken gesendet (Skelett + Skript, ~9 kB,
# nicht als Berry-Strings im Heap). Poll (~2 s): nur ein Daten-div < 400 Byte. Grafikdaten:
# chart.json mit den Puffern als Base64 (~1.9 kB), der Browser rechnet alles Übrige.

def uc3_chart_json()
  import webserver
  gplug_tag_pruefen()
  webserver.content_open(200, "application/json")
  webserver.content_send(string.format('{"t":%i,"n":%i,"p":"', gplug_tag0 * 86400, gplug_jetzt()))
  webserver.content_send(gplug_p.tob64())
  webserver.content_send('","e":"')
  webserver.content_send(gplug_e[0 .. 383].tob64())
  webserver.content_send('","b":"')
  webserver.content_send(gplug_b[0 .. 383].tob64())
  webserver.content_send('"}')
  webserver.content_close()
end

def uc3_sensor()
  var p = nil
  var e = 0
  var b = 0
  var v = 0.0
  if gplug_tag_pruefen()
    p = gplug_wert(gplug_p, gplug_index(gplug_jetzt()))
    e = gplug_summe(gplug_e, 96, 191)
    b = gplug_summe(gplug_b, 96, 191)
    v = gplug_verguetung(96, 191)
  end
  tasmota.web_send(string.format("<div id='gp_d' style='display:none' data-v='{\"p\":%s,\"e\":%i,\"b\":%i,\"v\":%.3f}'></div>",
    p == nil ? "null" : str(p), e, b, v))
end

def uc3_hauptseite()
  import webserver
  try
    var f = open(GPLUG_WD + "gplug_ui.html", "r")
    while true
      var s = f.read(2048)
      if size(s) == 0 break end
      webserver.content_send(s)
    end
    f.close()
  except .. as e, m
    webserver.content_send("<p>gPlug: gplug_ui.html fehlt in der App (" + str(m) + ")</p>")
  end
end
