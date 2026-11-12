# Compile gotchas, deploying/diagnosing on the device, testing off-device

Part of the skill `tasmota-lowmem-webui` — read only the section you need.

## 18. Berry compile gotchas (cheap to check before the device)

- A name must be **declared before its first use** in source order —
  `'x' undeclared` — also across files concatenated into one `autoexec.be`.
- No multi-line string literals (`unfinished string`).
- `tasmota.add_cron` patterns have **6 fields, seconds first**, local time.
- Hooks (`web_sensor`, `web_add_main_button`, `web_add_handler`,
  `every_second`, `save_before_restart`) are methods of an instance registered
  with `tasmota.add_driver()`; `webserver.on()` belongs in `web_add_handler()`.
- APIs that LLMs like to invent and that do not exist: `tasmota.http_get`,
  `tasmota.timer_set`, `tasmota.webserver.on`, `tasmota.file_read/write`,
  `tasmota.flag_get`, `tasmota.sensor_read`.

## 19. Deploying and diagnosing on a live device — safely

- Upload without the browser: `GET /ufsu` first (sets the upload type), then
  `curl -F "ufsu=@app.tapp;filename=app.tapp" "http://<ip>/ufsu?fsz=<size>"`;
  verify with `Br var f=open("/app.tapp","r") var n=f.size() f.close() return n` (not `size(f.readbytes())`: `bytes` is capped at ~32 kB and fails with `memory_error` on larger apps);
  then `Restart 1`.
- **Diagnostics run in the same heap.** A `Br` one-liner that fetches or builds
  something large on a device that is already near its limit reboots it — the
  measurement destroys what it measures. Prefer small read-only probes
  (`Status 11`, `tasmota.memory()`), or reproduce off-device (§20).
- Tasmota's web-console log (`/cs?c2=0`) is a small ring buffer; a chatty app
  (e.g. MQTT state every second) pushes your lines out within seconds. Give
  your app a status command (`tasmota.add_cmd("MyAppInfo", …)`) that reports
  counters, last error and heap, instead of relying on the log.
- Let `LoadAvg` settle after boot (§12) before trusting any number.

## 20. Test off-device first: desktop Berry from the same Tasmota tag

Build the Berry CLI from the Tasmota source tag that runs on the device
(`lib/libesp32/berry`, `make`; needs `berry_mapping`, `berry_int64`, `re1.5`,
`berry_custom` next to it). Its integer and float sizes match the device
(32-bit), so overflow and precision behave the same. Pointers are 64-bit, so
heap numbers are ~1.5–2× larger than on the device — compare relative changes,
not absolutes. The desktop CLI has no `load()` (use
`compile(path, "file")()`) and extra modules (`os`, `time`) that the device
lacks.

A thin Berry mock of `tasmota`, `webserver`, `webclient`, `persist`, `path`
plus a virtual clock that fires cron/timers in order lets you compile-check and
run scenario tests ("advance to 18:10, expect one fetch") in seconds — see
`emulator/` in the gplug-workshop repo. Make the mock *warn* about patterns that
are risky on the device (e.g. `get_string()` > 8 kB), since a desktop has
memory to spare and will never fail on its own.
