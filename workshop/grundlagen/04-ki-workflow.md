# 4 · Mit der KI bauen: Spec → /plan → /build

## Warum nicht einfach „bau mir eine gPlug-App“?

Weil das Modell dann rät: Es erfindet Tasmota-Funktionen, die es nicht gibt
(`tasmota.http_get`), parst 21 kB JSON auf einem Gerät mit 100 kB RAM und
meldet trotzdem „fertig“. Der erste Entwurf dieses Repos ist
genau so entstanden.

Was hilft: **klare Verträge und eine Maschine, die sie prüft.**

| Baustein | Wo | Wozu |
|---|---|---|
| Projektwissen | `AGENTS.md` (opencode), `CLAUDE.md` → `AGENTS.md` (Claude Code) | Fakten, Stolpersteine, Muster — liest der Agent bei jedem Start |
| Spezifikation | `spec/uc*.md` | Was soll die App tun? Schnittstellen + Testtabelle |
| Abnahmetests | ```` ```berry ````-Blöcke in `spec/uc*.md` | Prüfen jeden `UCx-N` im Emulator — von aussen |
| Werkzeuge | `build.sh`, `test.sh` | Echter Compiler, echter Testlauf: der Agent sieht seine Fehler selbst |
| Befehle | `.opencode/commands/`, `.claude/commands/` | `/plan` liest und plant (nur lesen), `/build` schreibt, baut, testet, lädt in den Emulator |
| Skill | `.claude/skills/tasmota-lowmem-webui/` | Erprobte Muster für WebUI und Heap |

## Der Ablauf

```
spec/uc1-preise.md ──/plan──▶ Plan im Chat ──/build──▶ gplug/uc1_preise.be
                                                       │
            ┌──── FEHLER UC1-4 … ◀── test.sh ◀── build.sh
            └──▶ Agent korrigiert, baut, testet erneut … bis grün
                 → build/gplug.tapp, App im Emulator geladen
```

1. **Spec lesen** (du!): Stimmt, was da steht? Passt es zu deinem gPlug
   (`Status 10` → heissen die Zähler `Eo`/`Ei`)?
2. **`/plan ucN`** (neue Sitzung pro Use Case): Der Agent schreibt einen Plan in den Chat und
   ändert nichts. **Lies ihn.** Hier ist eine Korrektur noch billig: falsche APIs,
   `json.load`, Listen statt `bytes()`.
3. **`/build ucN`**: Code entsteht. Der Agent baut nach jeder Datei mit `build.sh` und testet mit
   `test.sh gplug ucN`. Am Schluss baut er immer: `build/gplug.tapp` und App im Emulator. Rot → er liest den Fehler und korrigiert die **App** (nicht die Tests).
4. **Im Emulator ansehen** (`http://localhost:8080/emu`): Sieht die Grafik so aus, wie du willst?
5. **Eigene Änderungen** mit `/build <Auftrag>`: Code + Zeile in der Spec-Testtabelle + Test gemeinsam.

Ablauf im Detail: `workshop/teilnehmende.md`, Abschnitt 3.

## Gute Anweisungen

- Klein schneiden: `/build uc1` statt „bau die ganze App“ — ein Use Case pro Sitzung.
- Fehler zurückgeben statt beschreiben: Test-Ausgabe einfügen.
- Grenzen nennen: „Ändere nichts in `spec/` — weder Text noch Testblöcke.“
- Wissen einfordern: „Prüfe jede Tasmota-Funktion gegen AGENTS.md.“

## opencode oder Claude Code?

Beide laufen **im Container** — gleich unter Windows, macOS und Linux:

| | opencode | Claude Code |
|---|---|---|
| Start | `docker compose run --rm opencode` (Terminal) oder `docker compose up opencode-web` (Browser, http://localhost:4096) | `docker compose run --rm claude` |
| Modell | Qwen3.5 397B über Infomaniak (Schweiz), aus `.env` | Claude (eigener Zugang, Login im Container oder `ANTHROPIC_API_KEY`) |
| Projektwissen | `AGENTS.md`, `.opencode/commands/`, Skills | `CLAUDE.md` → `AGENTS.md`, `.claude/commands/`, Skills |
| Bauen/Testen | `bash build.sh`, `bash test.sh` direkt im Container | ebenso |
| Emulator | `http://emulator:8080` (`$EMU_URL`) | ebenso |

Beide arbeiten auf denselben Dateien — man kann wechseln. Wer Claude Code schon
auf dem Notebook installiert hat, kann es auch dort nutzen; Bauen und Testen dann
mit `docker compose run --rm tools bash test.sh`.
