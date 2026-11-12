# main.be — Treiber, Zeitpläne, Start (wird von build.sh zuletzt angehängt)
#
# Start: Konfiguration und gespeicherte Daten laden, auf die Uhr warten (vor NTP ist
# local ~0), dann verpassten Tagesabschluss nachholen und fehlende Tarife holen.

class GplugApp
  def web_add_handler()
    import webserver
    webserver.on("/gplug/chart.json", / -> uc3_chart_json(), webserver.HTTP_GET)
  end
  def web_add_main_button() uc3_hauptseite() end
  def web_sensor() uc3_sensor() end
  def save_before_restart()
    uc1_speichern()
    uc2_speichern()
  end
end

def gplug_laden()
  gplug_cfg_laden()
  var t1 = uc1_laden()
  var t2 = uc2_laden()
  gplug_tag0 = t1 > t2 ? t1 : t2
  gplug_p = gplug_angleichen(gplug_p, t1)
  gplug_e = gplug_angleichen(gplug_e, t2)
  gplug_b = gplug_angleichen(gplug_b, t2)
end

def gplug_start()
  if !gplug_tag_pruefen()
    tasmota.set_timer(5000, gplug_start, "gplug_start")
    return
  end
  uc4_abschluss()
  if uc1_noetig() uc1_abruf() end
end

def gplug_stuendlich()
  if gplug_tag_pruefen() && uc1_noetig() uc1_abruf() end
end

gplug_laden()
var gplug_app = GplugApp()
tasmota.add_driver(gplug_app)
for id: ["gplug_vs", "gplug_min", "gplug_abruf", "gplug_csv"] tasmota.remove_cron(id) end
tasmota.add_cron("0 */15 * * * *", uc2_viertelstunde, "gplug_vs")
tasmota.add_cron("0 * * * * *", uc2_minute, "gplug_min")
tasmota.add_cron("0 5 * * * *", gplug_stuendlich, "gplug_abruf")
tasmota.add_cron("0 1 0 * * *", uc4_abschluss, "gplug_csv")
tasmota.set_timer(2000, gplug_start, "gplug_start")
tasmota.set_timer(20000, uc2_start, "gplug_zaehler")
log("GPL: gPlug-App " + GPLUG_VERSION + " gestartet", 2)
