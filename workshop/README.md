# Leitfaden für die Workshop-Leitung

**Workshop:** Eine eigene gPlug-App für die Vergütung 2027 bauen
**Wann/Wo:** Do 12.11.2026, 17:00–20:00, Glue AG, Schwarztorstrasse 31, Bern
**Leitung:** Michael Bieri

## Material

| Datei | Inhalt |
|---|---|
| [praesentation/index.html](praesentation/index.html) | Folien (im Browser öffnen, ←/→, `F` = Vollbild), offline lauffähig |
| [teilnehmende.md](teilnehmende.md) | Schritt-für-Schritt-Anleitung (vorab verschicken) |
| [grundlagen/](grundlagen/) | 1 gPlug/Tasmota/Berry · 2 Vergütung & BKW-API · 3 WebUI & Speicher · 4 KI-Workflow · 5 Emulator & Tests |
| `../referenz/gplug/` | Referenzlösung, 13 Testblöcke / 45 Tests grün |
| `../spec/` | Aufgabe und Abnahme: UC1–UC4 Pflicht, UC5 (Zählernamen aus dem Skript) und UC6 (Befehle) Zusatz. Jede Spec: Vertrag, Regeln, Testtabelle, eingeklappter Testcode; kein Use Case braucht einen späteren |

## Ablauf (180 min)

| Zeit | Block | Inhalt |
|---|---|---|
| 17:00 | Begrüssung (10') | Ziel des Abends, Runde: wer hat welchen gPlug, welche KI-Erfahrung |
| 17:10 | Input (25') | Allgemeiner Teil (gPlug, `Status 10`, Vergütung & BKW-Tarif) hält eine andere Person, nicht in den Folien. Danach Folien: Berry, die Speichergrenze (Live-Demo `json.load` → Neustart als Video/Erzählung), Aufgabe, KI-Workflow, Setup |
| 17:35 | Setup (20') | Docker läuft, `docker compose run --rm tools bash test.sh referenz` grün, Emulator offen, `.env` mit Infomaniak-Zugang, `Status 10` am eigenen gPlug |
| 17:55 | Demo (10') | Leitung macht `/plan uc1` + `/build uc1` live mit opencode; zeigt einen roten Test und wie der Agent ihn behebt |
| 18:05 | Bauen I (45') | UC1 + UC2 bis grün; Coaches gehen herum |
| 18:50 | Pause (10') | |
| 19:00 | Bauen II (35') | UC3 + UC4; im Emulator mit Zeitraffer einen Tag durchspielen. Wer schneller ist: UC5, dann UC6 |
| 19:35 | Deploy (15') | `.tapp` auf den eigenen gPlug, Kacheln/`chart.json` (mit UC6 `GplugInfo`), Heap prüfen |
| 19:50 | Abschluss (10') | Was lief, was nicht; Erweiterungsideen; Feedback |

Wer nicht fertig wird: Referenzlösung bauen (`docker compose run --rm tools bash build.sh referenz/gplug build/referenz`)
und `build/referenz/gplug.tapp` laden — niemand geht ohne laufende App nach Hause.

## Vorbereitung

### 1 Woche vorher
- [ ] `teilnehmende.md` Schritt 0 an alle verschicken (Docker Desktop + `docker compose build` zu Hause)
- [ ] Mindestens einmal auf **Windows** durchspielen (PowerShell, Docker Desktop mit WSL 2)
- [ ] Infomaniak AI Tools: **ein Token pro Teilnehmer/in** (oder eins mit Limit) im Produkt 105617 erzeugen.
      Modell `Qwen/Qwen3.5-397B-A17B-FP8` ist in `.env.example` voreingestellt (gplug-ch/ki-workshop nutzt Qwen3.5-122B, das unser Produkt nicht anbietet; Alternative Kimi-K2.6).
      Verbindung prüfen: `docker compose run --rm opencode modelle`
- [ ] Mit diesem Modell einmal den ganzen Ablauf durchspielen (pro Use Case `/plan` → `/build`, bis alle Tests grün) — auch einmal auf Windows und Zeit messen
- [ ] Entscheiden: sollen Teilnehmende die Referenzlösung sehen?
      Wenn nein → Branch `teilnehmende` ohne `referenz/` erzeugen und diesen klonen lassen:
      `git switch -c teilnehmende && git rm -r referenz && git commit -m "Ohne Referenz"`
      (dann in `teilnehmende.md` die Referenz-Zeilen und in `test.sh` den Fall `referenz` beachten)

### Am Tag
- [ ] WLAN-Zugang für Gäste, gPlugs müssen ins gleiche Netz wie die Notebooks (oder eigene gPlugs im Heimnetz lassen und nur `.tapp` mitnehmen)
- [ ] USB-Stick mit `docker save -o images.tar gplug-workshop-tools gplug-workshop-agent` je für amd64 und arm64 (für alle, deren Build zu Hause nicht klappte: `docker load -i images.tar`)
- [ ] Zwei Ersatz-gPlugs mit Tasmota 15.3 und Testzähler-Daten
- [ ] Beamer: Präsentation + Referenzlösung (`docker compose up -d referenz` → http://localhost:8090/emu)

## Troubleshooting

| Symptom | Ursache / Lösung |
|---|---|
| `port is already allocated` | `EMU_PORT=8081` in `.env` |
| Browser zeigt „Seite nicht erreichbar“ | Adresse **mit `http://`** eingeben — Safari/Chrome („Immer sichere Verbindungen“) machen sonst `https://` daraus, das der Emulator nicht kann |
| Emulator läuft, aber http://localhost:8080 antwortet nicht | `docker ps` zeigt nur `8080/tcp` ohne `0.0.0.0:8080->` → Port war beim Start belegt. `docker compose up -d --force-recreate emulator` (oder anderer `EMU_PORT`) |
| `FEHLER: Berry-Compiler nicht gefunden` | `./build.sh` auf dem Host gestartet → `docker compose run --rm tools bash build.sh` |
| `'x' undeclared` beim Build | Funktion/Variable vor der Definition benutzt, oder Datei-Reihenfolge (alphabetisch, `main.be` zuletzt) |
| Agent nutzt `tasmota.http_get` & Co. | auf `AGENTS.md` → „Berry compile gotchas“ verweisen; der Build-Fehler zeigt es ohnehin |
| Tests grün, aber Grafik leer im Emulator | Zeit vorspulen (Energie erst nach der nächsten Viertelstunde); BKW-Modus `fixture` |
| opencode: Authentifizierungsfehler | `.env`: Token/Produkt-ID; `docker compose run --rm opencode modelle` testet die Verbindung |
| opencode: Modell kennt Werkzeuge nicht | Modell mit Tool-Calling wählen (Qwen3.5 und Kimi K2 können es) |
| gPlug startet nach App-Upload neu | Heap: `json.load` auf der BKW-Antwort? Listen statt `bytes()`? → `gplug.tapp` löschen, im Emulator prüfen |
| Kacheln Einspeisung/Bezug bleiben 0 bzw. leer | Schlüssel stimmen nicht → `Status 10` ansehen, `/gplug.json` mit `key_ein`/`key_bez`/`einheit` anlegen (UC2), Neustart |
| Tarife fehlen am Gerät | HTTPS-Webclient fehlt in der Firmware (bei gPlug-Firmware 15.3 vorhanden); Log ansehen (`GPL:`), mit UC6 `GplugAbruf` |
| Linux: Dateien in `build/` gehören root | Container laufen als root; `sudo chown -R $USER build emulator/fs` |
| Windows: `bash\r: No such file` / `$'\r': command not found` | Repo wurde vor `.gitattributes` mit CRLF ausgecheckt → `git rm --cached -r . && git reset --hard` oder neu klonen |
| `docker: 'compose' is not a docker command` oder `unknown flag: --profile` | Altes Docker mit `docker-compose` v1: `docker-compose` statt `docker compose` schreiben (ab 1.25; Profile gibt es im Repo keine mehr). Ältere v1: Docker Desktop bzw. Compose v2 installieren |
| Windows: `permission denied` bei `./build.sh` | `bash build.sh` bzw. `bash test.sh` verwenden (so stehen sie überall in den Unterlagen) |
| Windows: `$'\r': command not found` oder `bash\r: No such file` | Zeilenenden CRLF: Repo ohne `.gitattributes` kopiert/entpackt → neu klonen mit git, dann `docker compose build` |
| Windows: Emulator langsam beim Bauen | normal bei Bind-Mounts unter Windows; Repo im WSL-Dateisystem (`\\wsl$\…`) klonen ist schneller |
| opencode: `Provider request failed with HTTP 400` | Modell-Limits fehlen → `INFOMANIAK_CONTEXT`/`INFOMANIAK_OUTPUT` in `.env` (Standard 80000 / 16384 wird automatisch gesetzt) |
| opencode hängt ohne Ausgabe | Startskript nutzt `--standalone`; bei eigenem Aufruf `opencode --standalone` verwenden |
| opencode-Terminal sieht schlecht aus (Farben, Rahmen) | Terminal mit 24-Bit-Farben verwenden (iTerm2, Windows Terminal, Ghostty) und `COLORTERM=truecolor` setzen — oder opencode im Browser: `docker compose up opencode-web` |
| opencode hängt, sobald ein zweites opencode läuft | Beide Container teilen die opencode-Datenbank (Volume `opencode-data`) — immer nur **ein** `docker compose run --rm opencode` gleichzeitig |
| opencode sehr langsam (Minuten pro Schritt) | Das Modell „denkt“ vor jeder Antwort (~25 Tokens/s bei Infomaniak). Standard ist darum Denken aus; `INFOMANIAK_THINKING=on` in `.env` nur bei Bedarf |
| Claude Code: Login im Container | Link aus dem Terminal im Browser öffnen, Code zurück ins Terminal kopieren; bleibt im Volume `claude-config` gespeichert |

## Fakten zum Weitererzählen (am gPlugK gemessen, 30.10.2026)

- Tasmota 15.3.0, ESP32-C3, ~114 kB Heap frei mit `gplug_ha.tapp` (Berry 34 kB)
- `json.load` der BKW-Antwort: **Neustart**
- `get_string()` mit unserer App + `gplug_ha`: 68 kB frei, 45 % fragmentiert → **nur 39 von 96** Viertelstunden, ohne Fehlermeldung
- `write_file()` + 1-kB-Stücke: 96 von 96, **90 kB frei**, Berry 57 kB
- Referenzlösung läuft auf dem Gerät: Tarife, Sensorzeilen (inkl. Bezug), `chart.json`, Grafik über Tasmotas Tabelle
- Über Mitternacht geprüft (30./31.10.): Stundenablesung um 00:00, CSV-Zeile um 00:01 (`2026-10-30;0.000;0.00;1.218;0.37;24`), Tarife „morgen“ werden zu „heute“; kein Neustart, 86 kB frei, Berry 58 kB
- Upload ohne Browser: `curl http://<ip>/ufsu` und `curl -F "ufsu=@build/referenz/gplug.tapp;filename=gplug.tapp" "http://<ip>/ufsu?fsz=<Bytes>"`, dann `Restart 1`
