# AGENTS.md — gplug-workshop

## Repo facts (verifiable)

- **Remote**: `https://github.com/proBieri/glue-workshop-smart-energy.git`
- **Branch**: `main`
- **Agent setup**: created with **opencode**. Commands (`/plan`, `/build`, see *Workflow*) and skills exist twice — `.opencode/{commands,skills}/` and `.claude/{commands,skills}/` — and must stay identical. `./agents-sync.sh` syncs both directions (newer file wins; deletions are not propagated — delete on both sides); `--check` only verifies. It runs automatically after every Claude Code edit (`.claude/settings.json` hook), in every `build.sh`, and in the git pre-commit hook (`.githooks/`, enable once per clone: `git config core.hooksPath .githooks`). **After editing a command or skill with opencode, run `./agents-sync.sh`.** `CLAUDE.md` only imports this file.
- **Skills** (`.opencode/skills/`, `.claude/skills/`): `tasmota-berry` — Berry syntax and the Tasmota API with verified examples; load it before writing any Berry code. `tasmota-lowmem-webui` — WebUI, heap, large HTTP responses, deployment; load it for any WebUI/chart/heap/fetch work.
- **Toolchain**: Docker only (`docker compose`); nothing needs to be installed on the host besides Docker.

## What this project is

**gPlug** — an IoT adapter that reads Swiss smart meters via their P1-DSMR (RJ12) or M-Bus interface and exposes meter data over MQTT. Runs Tasmota firmware on ESP32 hardware.

Models: **gPlugD** (WiFi), **gPlugE** (Ethernet), **gPlugK** (Kamstrup Omnipower slot), **gPlugM** (L+G SM E450 M-Bus).

## Key references

- **Tasmota docs**: <https://tasmota.github.io/docs/>
  - **Berry language and Tasmota API for this app → skill `tasmota-berry`** (section „Sprache kompakt“ + API, every example verified by its `pruefung.be`). **Load it before writing, planning or fixing Berry code.** `docs/BERRY_LANGUAGE_REFERENCE.txt` is only a local copy of <https://tasmota.github.io/docs/_media/BERRY_LANGUAGE_REFERENCE.txt> for humans — since 11.11.2026 no longer in the agents' system prompt (it cost ~6000 tokens per step, duplicated the skill, and describes things that fail on the device: assigning without `var` in strict mode, module `os`). Don't read it; the skill is authoritative where they differ (verified e.g. `string.replace` exists, `type([])` is `"instance"`, `int("abc")` is `0`).
  - Berry scripting (API reference: `tasmota`, `webclient`, `webserver`, `persist`, `path`, `bytes`, …): <https://tasmota.github.io/docs/Berry/>
  - P1-DSMR / Smart Meter Interface: `Features/Smart-Meter-Interface/`
  - MQTT: `MQTT/`
  - WebUI extension: `WebUI/` (for `web_sensor`, `web_add_main_button`)
- **gPlug docs**: <https://gplug.ch/faq/>
- **OBIS codes**: P1-DSMR uses 5-digit OBIS codes (e.g. `1.1.1.7.0` = instantaneous grid power draw)
- **Tasmota Discord**: <https://discord.gg/Ks2Kzd4>

## What to watch for

- **Berry scripting** is the primary language — not Python. Tasmota's Berry, not PyCharm's Python.
- gPlug uses **ESP32** (no PSRAM on C3 variants) — memory-constrained.
- Smart meter data flows via **P1-DSMR** (RJ12) → parsed into OBIS codes → published via **MQTT**.

## This driver

Berry app for the gPlug (ESP32-C3, no PSRAM) built in the workshop "Eine eigene gPlug App für die Vergütung 2027 bauen" (Glue AG, 12.11.2026): fetches dynamic feed-in tariffs from the BKW API (`https://api.bkw.ch/api/dyntariffs/v1/Tariffs/energyreturn`, GET, no auth), records feed-in and import energy every quarter hour, renders a chart of yesterday/today/tomorrow in the Tasmota WebUI (tomorrow hidden until its prices exist) (1 SVG unit per quarter hour = 288 units, scaled to the box width — not device pixels; `chart.json` sends the int16 buffers as base64, tests decode via `T.chart()`), appends a daily billing row to a monthly CSV, and (optional, last use case) offers `Gplug*` console commands. Project docs (README, specs, workshop material) are in **German** — keep new docs in German.

Spec style (since 11.11.2026): a spec states **what** (contract, rules, test table); **how** (Berry/Tasmota calls, patterns) belongs in skill `tasmota-berry`. No references to real measurements, devices, testers or dates in `spec/` — those live here. Test code is folded under `<details><summary>Testcode …</summary>` (`test.sh` still finds the blocks).

### Layout

| Path | Content |
|---|---|
| `spec/` | Use cases `uc1-preise.md` … `uc6-befehle.md` (UC5 meter keys from the SML script and UC6 `Gplug*` commands optional; meter keys via `/gplug.json` are UC2; no test in UC1–UC5 may use a command) with interface contracts, test tables (`UCx-N`) and, below each table, the acceptance tests as ```` ```berry ```` blocks (`T.test("UCx-N …")`, black-box). `spec/README.md`: test helper API `T.*`, reading failures |
| `gplug/` | **Participants' app** — starts with a minimal `main.be` and the **given `gplug_ui.html`** (tiles, chart, tooltip; identical to `referenz/gplug/gplug_ui.html` — change both together). Agents must not change it or rebuild HTML/JS as Berry strings. |
| `referenz/gplug/` | Reference solution — passes all tests. **Hidden inside the agent containers** (`opencode`, `claude`: empty tmpfs over `referenz/`) so agents build from the spec instead of copying. Visible on the host, in `tools` and in the `referenz` emulator (:8090). |
| `emulator/` | Tasmota emulator: Berry mock of the Tasmota API (`mock/`), runner, test runner, web server + control panel |
| `docker/`, `docker-compose.yml` | Images `tools` (Berry from Tasmota v15.3.0 + Python, emulator) and `agent` (+ opencode v2 with Infomaniak config from `.env`, default model Qwen3.5-397B (`Qwen/Qwen3.5-397B-A17B-FP8`; 122B is not offered by our Infomaniak product), + Claude Code) |
| `workshop/` | Presentation, fundamentals, participant guide, facilitator guide |

### Workflow: spec → /plan → /build

Participants get `spec/` (contracts + executable tests) and generate plan and app themselves with **two commands** (`.opencode/commands/`, mirrored in `.claude/commands/`). **One use case per session** (`/new` in between), order uc1 … uc6; without an argument the first red one.

| Command | Mode | Does |
|---|---|---|
| `/plan ucN` | opencode agent `plan` (read-only, set in the command; Claude Code: switch to plan mode with `Shift+Tab` first) | reads spec (incl. its test blocks) and skill of this use case; plan **in the chat**, ≤ 40 lines, no code |
| `/build ucN` | agent `build` | writes `gplug/`, `bash build.sh` after each file, `bash test.sh gplug ucN` until green, then `bash test.sh`; **always ends with `bash build.sh`** → `build/gplug.tapp` and the app loaded into the emulator (`Emulator:  App geladen`) |

The detailed rules for writing code (file layout, `demo_eintraege`, Base64 in `chart.json`, name prefixes, stop rule) live in `.opencode/commands/build.md` — keep them there, not here. Test helper API `T.*`, reading failures, live-emulator `curl`s: `spec/README.md`. Own extensions beyond the spec: code + a row in the spec's test table + a `T.test("UCx-N …")` — no spec without tests, no tests without code.

**Windows:** call scripts as `bash build.sh` / `bash test.sh` (on Windows bind mounts the exec bit can be missing → `permission denied`). Line endings are forced to LF by `.gitattributes`; don't remove it (CRLF breaks bash and the image entrypoint).

### Build & test

Everything runs in Docker — also on Windows. The agent containers (`opencode`, `claude`) contain `berry`, Python and the repo at `/workshop`:

```bash
./build.sh [src] [out]                 # inside a container (needs `berry`); default gplug → build
./test.sh [gplug|referenz] [filter]    # e.g. ./test.sh gplug uc1
curl -s "$EMU_URL/cm?cmnd=GplugInfo"   # live emulator (EMU_URL=http://emulator:8080 in agent containers)
```

From the host: `docker compose up -d emulator` (emulator, http://localhost:8080/emu), `docker compose run --rm opencode|claude`, `docker compose run --rm tools ./test.sh`, `docker compose up -d referenz` (reference on :8090). Check `command -v berry` to know where you are. `docker-compose.yml` has **no profiles** and `version: "3.7"` so it also works with the old docker-compose v1 (≥ 1.25, `docker-compose` instead of `docker compose`; verified 09.11.2026 with 1.25.0 and 1.29.2) — always name the service in `up` (`up -d emulator`), a bare `up -d` starts every service.

`build.sh` step 5 loads the new app into the running emulator whose build dir matches (`POST /emu/api/laden`, prints `Emulator: App geladen`, exit 1 if the app fails to load); without a running emulator it only prints a note. The emulator also still reloads on its own when `build/autoexec.be` changes.

- `build.sh` rejects names that compile in the emulator but don't exist on the device (`_emu_*`, `T.*`, `float(`, `len(`, `import os|time`, fake `tasmota.*` APIs) with `file:line` and the fix. `T.chart()` fails with `chart.json (spec/uc3-webui.md): …` when `p`/`e`/`b` are not Base64 of the right length — before 05.11.2026 it silently returned empty lists and opencode/Kimi spent ~50 steps on `index_error` inside the test file.
- `build.sh` concatenates `src/*.be` **alphabetically, `main.be` last** (one global namespace), copies other files (e.g. `gplug_ui.html`) next to it, compiles with `emulator/compile.be` (maps errors back to `file:line`), packs `gplug.tapp` (stored ZIP). It exits 1 on any error — no placeholder outputs.
- `test.sh` extracts every ```` ```berry ```` block from `spec/ucN-*.md` into its own file (other lines blank, so line numbers = spec line numbers; output shows `spec/…md:<line>`) and runs each block in a fresh emulator: Wed 2026-11-11 10:00 CET, empty FS, BKW fixture, simulated meter.
- Emulator vs. device: desktop Berry 1.1.0 from Tasmota v15.3.0, 32-bit int and float like the device, but 64-bit pointers (heap ~1.6× larger) and extra modules (`os`, `time`) that don't exist on the device. The emulator's Berry is built with line info: runtime errors show a stack traceback with `gplug/<file>.be:<line>` (on the device only the error name).

### Verified facts (measured on a gPlugK, Tasmota 15.3.0, ESP32-C3)

- `Status 10` / `tasmota.read_sensors()`: `{"Time":…,"z":{"SMid":…,"Pi":W,"Po":W,…,"Ei":kWh,"Eo":kWh,"rEi":…,"rEo":…}}` — prefix `z`, `Eo` = feed-in total, `Ei` = import total (kWh, 3 decimals).
- Meters with tariff registers (tester, 02.11.2026) report no `Ei`/`Eo`, only `Ei1`/`Ei2`, `Eo1`/`Eo2` (kWh) and `Pi`/`Po` in **kW** (`"Pi":1.850`) — the app sums `key1 + key2 …` when `key` is missing.
- The meter's names and units are defined in the Tasmota Scripter SML script (`>M` section), e.g. `1,1-0:2.8.1(@1,Eo1 ___ 2⋅8⋅1,kWh,Eo1,3` = OBIS 2.8.1 → JSON `Eo1` in kWh; the `@` divisor is already applied in `Status 10`. The reference app reads `/script.txt` line by line 20 s after start (UC5, see `spec/uc5-zaehlerschluessel.md`). Verified 02.11.2026 on a gPlugD (Tasmota 15.5.0, ESP32-C3): the active script is the file `/script.txt` (identical to the Scripter editor `/s10`), Berry reads it with `open()`/`readline()`. Other firmwares/models not checked.
- **`json.load()` of the full 21 kB BKW response rebooted the device** (heap exhausted).
- **`get_string()` of the same response is not safe either**: with `gplug_ha.tapp` also loaded (68 kB free, 45 % fragmentation) it was silently truncated (39 of 96 entries); holding a second copy rebooted the device. Use `webclient.write_file("/x.tmp")` and scan the file in 1 kB chunks (`f.read(1024)`), carrying an unfinished record over — reference: `referenz/gplug/uc1_preise.be`. Result on the device: all 96 entries, ~90 kB free.
- All `.tapp` apps share one Berry VM (namespace + heap). With the reference app plus `gplug_ha.tapp`: Berry `HeapUsed` 55–57 kB, `heap_free` ~90 kB.
- BKW API returns 96 quarter-hours (UTC) for **today before ~18:00, tomorrow after**.
- Since 05.11.2026 the BKW prices change **every quarter hour** (Swiss control zone switched to 15-min prices); until 04.11. the four quarter hours of an hour had the same value. Never assume hourly prices. Sample: `emulator/fixtures/bkw_energyreturn_2026-11-05.json`.
- **Feed-in tariff ≠ consumption tariff.** The BKW API (`energyreturn`) only provides the feed-in tariff. The consumption (Bezug) tariff is unknown — never compute or display costs for consumption; show Bezug only as energy (kWh). "Costs" only arise from feed-in at negative prices (negative Vergütung).
- `tasmota.wd` is only set **while** a `.tapp` is loading — capture it in a global at load time.
- On boot Tasmota loads the `.tapp` **before NTP**: at load time `rtc()["local"]` is ~0. Anything day-based run in a constructor (e.g. shifting day buffers to "today") must wait for `rtc()["utc"] > 1700000000`, otherwise it wipes the data just loaded from flash (seen 05.11.2026: prices re-fetched after every restart). The emulator starts with a valid clock, so the tests don't catch this.
- Diagnostics run in the same heap: a heavy `Br` one-liner on a device near its limit reboots it. Probe with `Status 11` / `tasmota.memory()` / the app's `GplugInfo`, reproduce heavy things in the emulator.
- Upload without a browser: `curl http://<ip>/ufsu` then `curl -F "ufsu=@build/gplug.tapp;filename=gplug.tapp" "http://<ip>/ufsu?fsz=<bytes>"`, then `Restart 1`.
- `tasmota.strptime()` returns a map incl. `epoch`; `time_dump` `weekday` is 0 = Sunday.

### Token budget (agents pay per step for everything in the conversation)

Measured with opencode/Kimi on UC1: 85 steps, context grew to 125k tokens, 5.4M input tokens — mostly from reading files. Every file you read stays in the conversation and is paid again on each following step. Measured 01.11.2026: three sessions with ~220 steps each, 18–27M input tokens each — most of it **debugging by trial and error**.

- **Never modify** `build.sh`, `test.sh`, `emulator/` or the test blocks in `spec/` to make your code pass — fix the app (test blocks change only together with their test table). In the agent containers these are read-only or hidden anyway.
- **Don't read** `emulator/` internals (`mock/*.be`, `testrunner.be`, `server.py`) — the test helper API `T.*` is documented in `spec/README.md`. `emulator/fixtures/`, `referenz/` are hidden in the agent containers anyway.
- **Don't re-read your own files** after writing/editing them — you know their content; use `grep -n` or a small `offset`/`limit` range when you need to check a spot.
- Read the spec **of the use case you work on**, not all of them; the BKW response format is in `spec/uc1-preise.md` (no need to fetch or open full responses).
- Run tests filtered (`./test.sh gplug uc1`) while working on one use case; the full run only at the end.
- **Debug from the traceback, not by experiment.** `BRY: Exception>` is followed by `gplug/<file>.be:<line>: in function …` — open exactly that range (`offset`/`limit`) and fix it. No `berry -e` experiments, no `test_debug*.be` or helper scripts in the repo, no Python scripts that rewrite `.be` files — use the edit tool.
- At most **one** round of temporary `log("GPL: …")` lines per bug, filtered with `./test.sh gplug uc2 2>&1 | grep -E "GPL:|FEHLER"`; remove them in the same step as the fix.
- **Stop rule:** if the same test is still red after 3 fix attempts, stop and report (test, file:line, hypothesis) instead of continuing — the participant decides.
- Keep `.be` files under ~150 lines and edits small; write a large file in two steps (create, then append with edit) — large `write` calls failed repeatedly as invalid JSON.

Measured 05.11.2026 (opencode/Kimi K2.6, former `/plan` + `/implement` commands in one session): 119 tool calls, 4 compactions, step limit reached with UC1 still red. Causes: `chart.json` sent `p` as a JSON list (contract only in the UC3 spec), `_emu_tz_offset` copied from a test, a self-written chunk parser instead of the skill's `demo_eintraege`. Hence: one use case per session (`/new` between use cases), contract repeated in `spec/uc1-preise.md`, without a named use case only the first red one.

Measured 09.11.2026 (opencode, Qwen3.5-397B, `/plan` + `/build` per use case, new session each, spec with embedded test blocks): all 7 test blocks green after 33 min (UC1 4 min, UC2 11.5, UC3 10, UC4 5.5, UC5 1), 333 steps, 15.2M tokens (94 % cache), ~1.50 USD. But: files of 190–574 lines despite the 150-line rule, the UC3 session broke UC2-8 (fixed again by UC5), the HTML/JS ended up as Berry strings in `uc3_webui.be` instead of a file in the `.tapp`, and the page **looks broken** (empty tiles, tiny chart, no price line) although UC3-1…5 are green — the visual parts of UC3 are only checkable by eye. Review the page in the emulator after `/build uc3`.

### Berry compile gotchas

Skill **`tasmota-berry`** (`.opencode/skills/tasmota-berry/SKILL.md`, mirrored in `.claude/skills/`) is the language/API reference the agents must load before writing code (German, every example verified in the emulator by its `pruefung.be`); `/plan` and `/build` require it. Measured 02.11.2026: without it, Gemma-4-31B guessed `float()` and never registered the `/gplug/chart.json` route. Keep it in sync when an API fact changes.


- A name must be **declared before its first use** in source order (`'x' undeclared`), across concatenated files too.
- Tasmota compiles apps in **strict mode**: assigning an undeclared name inside a function (`l = []` instead of `var l = []`) is `syntax_error … strict: no global 'l'` and the `.tapp` does not load (seen 05.11.2026 on a gPlug after all emulator tests were green). Since then `emulator/mock/emu.be` ends with `import strict`, so `build.sh` and the tests catch it too.
- No multi-line string literals (`unfinished string`).
- Only `.be` files are loaded by Tasmota (`autoexec.be` inside the `.tapp`).
- Tasmota APIs that do **not** exist: `tasmota.http_get`, `tasmota.timer_set`, `tasmota.webserver`, `tasmota.file_read/write`, `tasmota.flag_get`, `tasmota.sensor_read`. Use `webclient`, `add_cron`/`set_timer`, `import webserver`, `open()`/`path`, `persist`, `read_sensors()`.
- `web_add_main_button` / `web_sensor` / `web_add_handler` are methods of a class instance registered with `tasmota.add_driver()`.

## Berry / Tasmota — critical patterns

### Hooks: `web_sensor()` vs `web_add_main_button()`

- **`web_sensor()`** fires on **every** periodic AJAX poll (`/?m=1`, ~2-3s) and **replaces the entire sensor container's `innerHTML`** — wipes everything inside it.
- **`web_add_main_button()`** fires **once** per real page load (`/`), never on `/?m=1`.

**Rule**: put static/one-time markup in `web_add_main_button()`. Put only small, changing data in `web_sensor()`.

### Two data-delivery strategies (pick one)

| | Strategy | Pros | Cons |
|---|---|---|---|
| **§2** | Independent JSON endpoint (`webserver.on("/mydriver.json")`) + client `fetch()` | Independent poll cadence | Two HTTP requests per cycle; values can temporarily disagree with Tasmota's table |
| **§3** | Embed JSON inside `web_sensor()` + `MutationObserver` on `#l1` as trigger | One HTTP request; values always in sync | Poll cadence locked to Tasmota's native poll (~2-3s) |

### Binary encoding for charts

- Drop reconstructable dimensions (e.g. evenly-spaced X). Send remaining values as **raw bytes, base64-encoded** via `bytes().tob64()`.
- Only works when each value fits in a byte (0–255) — fine for pixel coordinates in small charts.

### Heap-conscious storage

- Use **`bytes()` ring buffers** (fixed-size, per-sample width), not Berry `list` of boxed values.
- `.get()` returns unsigned — decode signed 16-bit manually (`raw >= 32768 ? raw - 65536 : raw`).
- Return decoded values as **float**, not int — otherwise subsequent division silently becomes truncating integer division.

### String/literal costs (permanent heap)

- Berry's compiler does **not** constant-fold adjacent string literals. Each literal is its own permanent heap object.
- **Merge adjacent pure-text string literals** (no Berry variable between them) into one. Where a real variable sits between fragments, leave the split.
- **Memoize** computed-but-identical strings in a global variable if the render path fires more than once per boot.

### Config pattern

- Read settings from a small JSON file on the device filesystem at boot (`open("myapp.cfg", "r")`). Editable via Tasmota's built-in file manager. No UI needed.
- **Critical**: Berry's `bool()` treats ANY non-empty string as `true` (including `"false"`). Compare explicitly: `(v == true || v == 1)`.

### Diagnosing heap / latency

- `tasmota.memory()` → `gc_heap` (KB), `heap_free`, `frag` (%). Different pool from Tasmota's "Freier Arbeitsspeicher" and from `Status 11`'s whole-VM totals.
- Force `tasmota.gc()` and re-check: if `gc_heap` drops → accumulated garbage. If it doesn't move → permanent/retained (cache or fixed code cost, not a leak).
- Cross-check latency with `Status 11`'s `LoadAvg` and time an unrelated stock request (e.g. `Status 0`) to separate device-wide slowness from app-specific cost.
- Let `LoadAvg` settle ~1–2 minutes after boot (WiFi/MQTT/VPN reconnection spike).

### Move per-poll computation to the client

- If you're building SVG paths, axis labels, or formatted strings server-side from raw numbers, send the **raw numbers** and compute the presentation on the client. Browser JS does trig/loops/string-building for free vs. real recurring per-poll cost on Berry.

### When NOT to bother

- A driver with a handful of scalar values and no chart doesn't need the AJAX split, binary encoding, or ring buffers. Reach for each pattern because its specific symptom showed up, not by default.
