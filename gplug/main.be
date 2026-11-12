# main.be — Startpunkt deiner gPlug-App
#
# build.sh fügt alle gplug/*.be alphabetisch zusammen und hängt main.be
# zuletzt an. Lege pro Use Case eine Datei an (uc1_preise.be, …) und
# registriere hier Treiber und Zeitpläne. Spezifikation und Abnahmetests: spec/
#
#   bash build.sh              bauen, kompilieren, .tapp, in den Emulator laden
#   bash test.sh gplug uc1     Abnahmetests (```berry-Blöcke in spec/uc1-*.md)
#   http://localhost:8080/emu  Emulator (docker compose up -d emulator)

class GplugApp
  # Wird bei jeder Aktualisierung der Hauptseite aufgerufen (~alle 2 s)
  def web_sensor()
    tasmota.web_send("{s}gPlug-App{m}läuft{e}")
  end
end

var gplug_app = GplugApp()
tasmota.add_driver(gplug_app)
log("GPL: gPlug-App gestartet", 2)
