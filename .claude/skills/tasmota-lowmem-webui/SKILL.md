---
name: tasmota-lowmem-webui
description: Patterns for building or optimizing a Tasmota/Berry driver that contributes a web-UI section (web_sensor/web_add_main_button) on memory-constrained ESP32 targets (no PSRAM, e.g. ESP32-C3) and/or over slow links (VPN, low-power radio). Covers cutting recurring network traffic (AJAX skeleton/data split or embedding data in web_sensor() with a MutationObserver trigger, escaping Tasmota's periodic poll, binary-encoded chart data), moving recurring per-poll computation (SVG arc paths, chart axis labels) to client JS instead of just raw data, heap-conscious data structures (bytes() ring buffers, memoized HTML, string-literal consolidation), a no-reflash config-file pattern, diagnosing/reasoning about Berry heap usage and request-latency bottlenecks, fetching large HTTP/JSON responses without exhausting the heap (stream to flash with webclient.write_file and scan in chunks — json.load or get_string of ~20 kB rebooted a gPlug), several .tapp apps sharing one Berry VM, shipping static HTML as a file inside the .tapp (tasmota.wd), Berry compile gotchas, safe deployment/diagnosis on a live device, and testing off-device with the desktop Berry from the same Tasmota tag. Use whenever a Tasmota Berry app's web UI feels bandwidth- or heap-heavy, or before building a new one that will render live-updating values/charts.
---

# Tasmota/Berry: low-memory, low-traffic web UI

Distilled from a production gPlug dashboard and from a workshop reference app
tested on a real gPlugK (ESP32-C3, no PSRAM, Tasmota 15.3.0). **This file is the
short version.** Details, code samples and measurements are in `references/` —
open a reference file only when its topic is your current task (every file you
read stays in the conversation and costs tokens on each following step).

## Core rules

| # | Rule | Details |
|---|---|---|
| 1 | `web_sensor()` runs on **every** `/?m=1` poll (~2 s) and its output **replaces** `#l1`. `web_add_main_button()` runs **once** per page load. Put static markup in the latter and move your widget **before** `#l1` with JS. | webui.md §1 |
| 2 | Deliver changing data separately: a small JSON route (`webserver.on()` in `web_add_handler()`), fetched with a **relative** path. | webui.md §2 |
| 3 | Or embed small live values in `web_sensor()` as `<div id=… data-v='{json}'>` and use a MutationObserver on `#l1` as trigger — one request per poll, always in sync. | webui.md §3 |
| 4 | Send raw numbers, compact keys; compute SVG paths, scales, labels, sums in browser JS. Bytes+base64 for 0–255 series. One `<polyline>` per series, cap the point count. | webui.md §4, §5, §13 |
| 5 | Time series in `bytes()` (int16, marker for "empty"), not lists. `.get()` is unsigned → decode signed; return floats. | heap.md §6 |
| 6 | Every string literal is permanent heap; merge adjacent literals; memoize only if rendered often. | heap.md §7, §8 |
| 7 | Measure with `tasmota.memory()`, `tasmota.gc()`, `Status 11` — with **all** apps loaded; tell leaks from fixed cost. | heap.md §12 |
| 8 | Config via small JSON file read once at boot; never crash on bad input; `bool("false")` is true. | config-und-sensoren.md §9 |
| 9 | Meter counters: parse the number **from the text** into integer Wh (32-bit float loses Wh). Cross-check units; freshness needs a value that really changes. | config-und-sensoren.md §10, §11, §17 |
| 10 | **Never `json.load()` or `get_string()` a large HTTP response** (21 kB rebooted / silently truncated on a gPlug). `webclient.write_file()` to flash, scan with `f.read(1024)` chunks, carry unfinished records over, check completeness. | http-und-tapp.md §14 |
| 11 | All `.tapp` apps share **one Berry VM**: prefix globals, check `global()` for collisions, budget heap with everything loaded. | http-und-tapp.md §15 |
| 12 | Large static HTML/JS: a file inside the `.tapp`, read per page load via `tasmota.wd` — captured at **load time** (it is reset afterwards). | http-und-tapp.md §16 |
| 13 | Berry: declare before use; no multi-line strings; cron has 6 fields (seconds first); hooks are driver methods; no `tasmota.http_get`/`timer_set`/`webserver.on`/`file_read`. | geraet-und-tests.md §18 |
| 14 | Deploy: `GET /ufsu`, then `POST /ufsu?fsz=<bytes>` field `ufsu`; verify with `f.size()`; `Restart 1`. Diagnostics share the heap — no heavy `Br` one-liners on a loaded device. Expose a status command. | geraet-und-tests.md §19 |
| 15 | Test off-device with desktop Berry from the same Tasmota tag (32-bit int/float); heap there is ~1.6× larger. | geraet-und-tests.md §20 |

## When NOT to bother

These are fixes for observed problems on a genuinely memory/bandwidth
constrained target (ESP32 without PSRAM, a slow VPN link, a driver already
showing instability under load). A driver with a handful of scalar values
and no chart doesn't need the AJAX split, binary encoding, or ring buffers -
plain `web_sensor()` output is simpler and fine. Reach for each pattern here
because its specific symptom showed up, not by default.
