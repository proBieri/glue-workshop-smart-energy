# Anleitung für Teilnehmende

Ziel des Abends: Deine eigene Tasmota-App läuft auf deinem gPlug und zeigt
Einspeisung, Tarif und Vergütung der letzten Tage — gebaut mit einem KI-Agenten.

## 0 · Vorbereitung (zu Hause, 15 min)

Du brauchst nur **Docker Desktop** und **git** — Windows, macOS oder Linux.
Alle Befehle funktionieren gleich in PowerShell, im Mac-Terminal und in bash.

1. Docker Desktop installieren und starten: <https://www.docker.com/products/docker-desktop/>
   (Windows: mit WSL 2, wie vom Installer vorgeschlagen)
2. Repo holen und Images bauen (lädt ~1.5 GB — bitte zu Hause, nicht im Workshop-WLAN):
   ```bash
   git clone https://github.com/proBieri/glue-workshop-smart-energy.git
   cd glue-workshop-smart-energy
   docker compose build
   ```
   Windows: Repo in einen normalen Ordner klonen (z.B. `C:\Users\<name>\workshop`), nicht in
   OneDrive. Die Zeilenenden setzt das Repo selbst richtig (`.gitattributes`). Befehle mit
   Skripten immer als `bash build.sh` / `bash test.sh` aufrufen, nie `./build.sh`.

   Linux ohne Docker Desktop: Kennt dein Docker `docker compose version` nicht, aber
   `docker-compose version` (alte Version 1, ab 1.25), dann überall `docker-compose` statt
   `docker compose` schreiben — sonst gleich.
3. Prüfen:
   ```bash
   docker compose run --rm tools bash test.sh referenz    # endet mit "13 bestanden, 0 fehlgeschlagen"
   ```
4. gPlug: im eigenen Netz erreichbar? `http://<gplug-ip>/` im Browser öffnen.
   Firmware-Version unter *Information* notieren (getestet mit Tasmota 15.3.0).

## 1 · Den eigenen gPlug kennenlernen (15 min)

In der gPlug-WebUI → *Werkzeuge → Konsole* (oder im Browser):

```
http://<gplug-ip>/cm?cmnd=Status%2010
```

Heissen die Zählerstände `Eo` (Einspeisung) und `Ei` (Bezug) unter `"z"`?
Wenn nicht: Namen und Einheit (kWh oder Wh) notieren — sie kommen später in `/gplug.json`
(`{"key_ein": "…", "key_bez": "…", "einheit": "kWh"}`; mehrere Register mit `+`, z.B. `"Eo1+Eo2"`).

Freier Speicher: `Br tasmota.memory()` → `heap_free` notieren.

## 2 · Emulator und KI-Agent starten (15 min)

Zugangsdaten für Infomaniak bekommst du von der Leitung:

```bash
cp .env.example .env              # Windows PowerShell: copy .env.example .env
# .env im Editor öffnen: INFOMANIAK_API_KEY und INFOMANIAK_PRODUCT_ID eintragen

docker compose up -d emulator              # Emulator im Hintergrund
```

Browser: <http://localhost:8080/emu> (Port belegt? `EMU_PORT=8081` in `.env`).
Wichtig: Adresse **mit `http://`** eintippen — sonst macht der Browser evtl. `https://` daraus.
Keine Antwort, obwohl der Container läuft? `docker compose up -d --force-recreate emulator`.
Links eine Tasmota-Hauptseite mit deiner App (anfangs nur „gPlug-App läuft“),
rechts Uhr, Zähler-Simulator, Konsole und Log. Die fertige Referenzlösung zum
Vergleich: `docker compose up -d referenz` → <http://localhost:8090/emu>.

Dann den KI-Agenten starten — er läuft im Container, mit Compiler und Tests:

```bash
docker compose run --rm opencode      # opencode mit Qwen über Infomaniak (im Terminal)
```

Sieht die Terminal-Oberfläche unschön aus (Farben, Rahmen), nimm **opencode im Browser**:

```bash
docker compose up opencode-web
```

Den ausgegebenen Link öffnen (einmalig gültig, 5 Minuten; neuer Link mit
`docker compose exec opencode-web opencode-start link`). Dann *Projekt hinzufügen* →
`/workshop/` eintippen → Enter → *Ordner auswählen* → *Neue Sitzung*. Die Befehle
`/plan` und `/build` funktionieren dort genauso.
Nicht gleichzeitig mit der Terminal-Variante starten.

oder mit eigenem Claude-Zugang:

```bash
docker compose run --rm claude        # beim ersten Start: Link öffnen, Code einfügen
```

Der Agent erreicht den Emulator als `http://emulator:8080`. Jedes Mal, wenn er
neu baut, lädt `build.sh` die App gleich in den Emulator.

## 3 · Bauen lassen (90 min)

Du bekommst die Spezifikation (`spec/`, mit den Abnahmetests als Code unter jeder
Testtabelle). Plan und App
lässt du den Agenten selbst erzeugen, mit zwei Befehlen. Nur die Oberfläche
(`gplug/gplug_ui.html`: Kacheln, Grafik, Tooltip) ist vorgegeben — die App liefert ihr die Daten.

| Befehl | Modus | macht |
|---|---|---|
| `/plan uc1` | **plan** (nur lesen) | liest Spec, Tests und Skill des Use Case, schreibt einen Plan in den Chat |
| `/build uc1` | **build** | schreibt den Code in `gplug/`, baut, testet bis grün, erzeugt **immer** `build/gplug.tapp` und lädt die App in den Emulator |

In opencode schaltet `/plan` selbst in den plan-Modus und `/build` in den build-Modus.
In Claude Code vor `/plan` mit `Shift+Tab` den Plan-Modus einschalten, vor `/build` wieder aus.

Pro Use Case:

1. **Neue Sitzung** (`/new`, im Browser *Neue Sitzung*).
2. `/plan uc1` senden. **Plan lesen:** Nutzt er `webclient`, `add_cron`, `bytes()`? Parst er die
   BKW-Antwort ohne `json.load`? Wenn nicht: sagen, was falsch ist, neuen Plan verlangen.
3. `/build uc1` senden. Der Agent meldet am Schluss in fünf Zeilen, welche Tests grün sind und ob
   die App im Emulator geladen ist.
4. Im Emulator (<http://localhost:8080/emu>) ansehen, mit dem Zeitraffer einen Tag durchspielen.
5. Sind noch Tests rot, die Fehlermeldung wörtlich zurückgeben (gleiche Sitzung):
   ```
   bash test.sh zeigt:
   <Zeilen wörtlich einfügen>
   Behebe nur diesen Fehler, baue neu und teste erneut.
   ```

Reihenfolge: `uc1`, `uc2`, `uc3`, `uc4` (`uc5`, `uc6` als Zusatz). UC3 und UC4 brauchen die Daten aus
UC1 und UC2. **Nie zwei Use Cases in einer Sitzung**: der Agent bezahlt bei jedem Schritt den
ganzen bisherigen Verlauf. Gemessen am 05.11.2026: alle Use Cases in einer Sitzung, vier
Komprimierungen des Verlaufs, Schrittlimit erreicht, bevor UC1 grün war. Der Code bleibt in
`gplug/`, die nächste Sitzung baut darauf auf.

Was die Befehle an den Agenten schicken, steht in `.opencode/commands/plan.md` und `build.md` —
reinschauen lohnt sich, so sieht ein guter Auftrag aus.

Hängt der Agent (derselbe Test nach 3 Versuchen rot)? Abbrechen, neue Sitzung, gleichen Use
Case neu planen. Erfindet er Funktionen? Auf den Skill `tasmota-berry` und `AGENTS.md` →
„Berry compile gotchas“ verweisen.

Hört der Agent mitten in der Arbeit auf und steht am Ende Text wie `<arg_key>edit</arg_key>` oder
`[Assistant tool call]`? Das Modell hat einen Werkzeugaufruf als Text geschrieben, die Änderung
fehlt. Einfach `weiter` senden (gleiche Sitzung) — er macht dort weiter.

Fertig, wenn der Agent meldet (oder du selbst prüfst):
```bash
docker compose run --rm tools bash test.sh    # 13 bestanden, 0 fehlgeschlagen
```

Ohne die Zusätze UC5/UC6 ist der Gesamtlauf rot (deren 3 Blöcke fehlen) — dann zählt
`… test.sh gplug uc1` bis `uc4`: alle grün.

## 4 · Auf den gPlug laden (15 min)

1. `build/gplug.tapp` hat `/build` schon erzeugt (liegt im Repo-Ordner, auch unter Windows im Explorer sichtbar). Selbst bauen: `docker compose run --rm tools bash build.sh`
2. gPlug-WebUI → *Werkzeuge → Dateisystem verwalten* → *Datei auswählen* `gplug.tapp` → *Hochladen*
3. Konsole `Status 10`: heissen die Zählerstände `Eo`/`Ei` (oder `Eo1`, `Eo2` …/`Ei1`, `Ei2` …) in kWh, passt alles. Sonst im Dateisystem *Neue Datei* `gplug.json`, z.B. `{"key_ein":"Lief_HT+Lief_NT","key_bez":"Bezug_HT+Bezug_NT","einheit":"Wh"}` (Namen und Einheit aus `Status 10` bzw. dem Scripter-Skript)
4. *Werkzeuge → Neustart*
5. Hauptseite: Nach ~20 s erscheinen Tarif und Grafik (Energie erst ab der nächsten Viertelstunde)
6. Browser: `http://<gplug>/gplug/chart.json` antwortet (mit UC6 auch Konsole `GplugInfo` → `Preise_heute` = 96)
7. Speicher prüfen: `Br tasmota.memory()` — `heap_free` sollte deutlich über 50 kB bleiben

Entfernen: `gplug.tapp` im Dateisystem löschen, neu starten.

Die erste CSV-Zeile entsteht in der Nacht nach dem ersten vollen Tag:
*Dateisystem verwalten* → `gplug_JJJJ-MM.csv` herunterladen.

## 5 · Weiter (eigene Ideen)

- **Zeitumstellung** sauber behandeln (Tage mit 92 bzw. 100 Viertelstunden)
- Tageswerte per **MQTT** an Home Assistant
- Kosten des Bezugs, falls dein Netzbetreiber den (dynamischen) Bezugstarif per API anbietet — die BKW-API liefert nur den Einspeisetarif
- Grafik: Monatsübersicht aus der CSV

Bei jeder Erweiterung im build-Modus: Code, dazu eine Zeile in der Testtabelle der Spec und ein Test — keine Spec ohne Test, kein Test ohne Code.
