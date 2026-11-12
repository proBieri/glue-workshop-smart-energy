# 1 · gPlug, Tasmota und Berry

## Der gPlug

Der gPlug ist ein kleiner Adapter für Schweizer Smart Meter. Er steckt an der
Kundenschnittstelle des Zählers (P1/DSMR über RJ12, M-Bus oder im Kamstrup-Slot),
liest die Zählerdaten und stellt sie per WLAN/Ethernet bereit: Web-Oberfläche,
MQTT, HTTP.

| Modell | Anschluss |
|---|---|
| gPlugD | P1-DSMR (RJ12), WLAN |
| gPlugE | P1-DSMR, Ethernet |
| gPlugK | Kamstrup Omnipower (Steckplatz) |
| gPlugM | Landis+Gyr E450 (M-Bus) |

Innen arbeitet ein **ESP32-C3**: 160 MHz, 4 MB Flash, ~400 kB RAM — davon sind
im Betrieb noch **~100 kB frei**, **kein PSRAM**. Das ist die wichtigste
Randbedingung für alles, was wir bauen.

## Tasmota

Tasmota ist eine offene Firmware für ESP-Geräte. Auf dem gPlug liest Tasmotas
**Smart Meter Interface** (SML-Skript) die Zählerdaten und stellt sie als JSON bereit.
Ein echter gPlugK antwortet auf `Status 10` so:

```json
{"StatusSNS":{"Time":"2026-10-30T21:46:57","z":{"SMid":12345678,
  "Pi":847,"Po":0,"P1i":555,"V1":228,"I1":2.82,
  "Ei":7654.321,"Eo":234.567,"rEi":12.345,"rEo":2345.678}}}
```

| Schlüssel | Bedeutung | OBIS |
|---|---|---|
| `Ei` | Zählerstand Bezug, kWh | 1.8.0 |
| `Eo` | Zählerstand Einspeisung, kWh | 2.8.0 |
| `Pi` / `Po` | Leistung Bezug / Einspeisung, W | 1.7.0 / 2.7.0 |

Ausprobieren auf dem eigenen gPlug: `http://<gplug-ip>/cm?cmnd=Status%2010`

## Berry

Berry ist die Skriptsprache, die Tasmota auf dem ESP32 eingebaut hat. Sie sieht
aus wie eine Mischung aus Python und Lua, ist aber **kein Python**.

```berry
class Hallo                       # Klasse
  var zaehler                     # Instanzvariable
  def init() self.zaehler = 0 end
  def every_second()              # von Tasmota jede Sekunde aufgerufen
    self.zaehler += 1
  end
  def web_sensor()                # Zeile in der Sensortabelle der Hauptseite
    tasmota.web_send(format("{s}Hallo{m}%i s{e}", self.zaehler))
  end
end
tasmota.add_driver(Hallo())       # als Treiber registrieren
```

| Python-Gewohnheit | Berry |
|---|---|
| Einrückung | `if … end`, `def … end`, `while … end`, `for x: liste … end` |
| `range(0, 24)` | `for i: 0 .. 23` |
| `str[1:4]` | `s[1 .. 3]` (inklusive Ende) |
| `"""mehrzeilig"""` | gibt es nicht — ein String steht auf einer Zeile |
| `dict.get(k)` | `map.find(k)` |
| `None` | `nil` |
| `7 / 2 = 3.5` | `7 / 2 = 3` (int!), `7 / 2.0 = 3.5` |

## Die wichtigsten Tasmota-APIs für die App

| Zweck | Berry |
|---|---|
| Treiber mit Hooks | `tasmota.add_driver(obj)` → `every_second`, `web_sensor`, `web_add_main_button`, `web_add_handler`, `save_before_restart` |
| Zeitplan | `tasmota.add_cron("0 0 * * * *", f, "id")` — **6 Felder, Sekunden zuerst**, lokale Zeit |
| einmal später | `tasmota.set_timer(20000, f, "id")` (ms) |
| Uhrzeit | `tasmota.rtc()` → `{'utc':…, 'local':…, 'timezone':60}` |
| Zählerdaten | `tasmota.read_sensors()` → JSON-**Text** wie `Status 10` |
| HTTP-Abruf | `var cl = webclient() cl.begin(url) cl.GET() var s = cl.get_string() cl.close()` |
| eigene URL | `import webserver` → `webserver.on("/pfad", f, webserver.HTTP_GET)` in `web_add_handler()` |
| Dateien | `open("/datei.csv", "a")`, `import path` → `path.exists/listdir/remove` |
| Werte über Neustart | `import persist` → `persist.x = 1 persist.save()` |
| Konsolenbefehl | `tasmota.add_cmd("GplugInfo", def (cmd, idx, payload) … end)` |
| Log | `log("Text", 2)` |

Diese Befehle gibt es **nicht** (KI-Modelle erfinden sie gern):
`tasmota.http_get`, `tasmota.timer_set`, `tasmota.webserver.on`, `tasmota.file_read`,
`tasmota.flag_get`, `tasmota.sensor_read`.

Referenz: <https://tasmota.github.io/docs/Berry/>

## Eine Tasmota-App (.tapp)

Eine `.tapp` ist ein **ZIP ohne Kompression** mit einer `autoexec.be`. Tasmota
startet beim Booten jede `.tapp` im Dateisystem. Weitere Dateien im ZIP (z.B.
HTML) erreicht man über `tasmota.wd + "datei"` — `tasmota.wd` ist aber nur
**während des Ladens** gesetzt, also gleich am Anfang in eine Variable kopieren.

## Stolpersteine beim Kompilieren

- **Erst definieren, dann benutzen.** Berry übersetzt von oben nach unten. Ruft
  `uc4_tagesabschluss()` eine Funktion auf, die weiter unten steht, meldet der
  Compiler `'uc4_aufraeumen' undeclared`. Das gilt auch über Dateigrenzen:
  `build.sh` fügt die Dateien alphabetisch zusammen, `main.be` zuletzt.
- **Ein Namensraum.** Alles ist global — Präfixe (`uc1_`, `gplug_`) verhindern Kollisionen.
- **`bool("false")` ist `true`.** Werte aus Dateien explizit vergleichen.
