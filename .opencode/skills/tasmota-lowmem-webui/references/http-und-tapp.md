# Large HTTP responses, several apps per VM, assets in the .tapp

Part of the skill `tasmota-lowmem-webui` — read only the section you need.

## 14. Large HTTP responses: never hold them whole — stream to flash, scan in chunks

Measured on a gPlugK (ESP32-C3, Tasmota 15.3.0) fetching a 21 kB JSON price
feed (96 entries) over HTTPS:

| Approach | Result on the device |
|---|---|
| `get_string()` then `json.load()` | **reboot** (heap exhausted — the object tree is many times the text size) |
| `get_string()`, scan text, app alone on the device (~114 kB free) | works, ~95 kB free afterwards |
| `get_string()`, same app with a second `.tapp` loaded (68 kB free, 45 % fragmentation) | **silently truncated**: only 39 of 96 entries arrived, no error |
| a second 21 kB string held at the same time (diagnostic `Br` call) | **reboot** |
| `write_file()` to flash, then `f.read(1024)` chunk scan | all 96 entries, **~90 kB free**, fragmentation 32 % |

`get_string()` needs one contiguous allocation of the full body. Whether it
succeeds depends on everything else loaded on the device, so it can pass on
your bench and fail at a customer's. Stream instead:

```berry
var cl = webclient()
cl.begin(url)
var code = cl.GET()
var n = code == 200 ? cl.write_file("/myapp.tmp") : 0   # streams body to flash
cl.close()
# then scan the file in chunks, carrying an unfinished record into the next chunk
var f = open("/myapp.tmp", "r")
var rest = ""
while true
  var part = f.read(1024)
  var last = size(part) == 0
  var s = rest + part
  var pos = 0
  # ... string.find() records in s from pos; stop (break) if a record may be cut off
  #     at the end of s and !last; set pos past each complete record ...
  rest = pos < size(s) ? s[pos ..] : ""
  if last break end
end
f.close()
path.remove("/myapp.tmp")
```

- Validate completeness (e.g. expected 96 records) — truncation does not raise.
- Never `json.load()` a response larger than a few kB; search the text for the
  fields you need (`string.find`, then slice the value).
- One file write per fetch is negligible flash wear (once per hour/day).

## 15. Several apps share one Berry VM — namespace and heap budget

All `.tapp` files and `autoexec.be` run in the **same** Berry VM: one global
namespace, one heap. A gPlug that already runs a vendor app (here
`gplug_ha.tapp`, Berry heap 34 kB) has much less room than an empty one: adding
a ~500-line app raised Berry `HeapUsed` from 34 to 55 kB and dropped `heap_free`
from ~114 to ~68 kB until the fetch was made streaming.

- Prefix every global (`myapp_`, `MYAPP_`); before deploying, list the device's
  globals and check for collisions:
  `Br import global var l=[] for n: global() l.push(n) end return l`
- Measure the heap budget **with all apps loaded**, after a forced
  `tasmota.gc()`, and keep a large margin for transient peaks (TLS handshake,
  page render).
- Make reloads idempotent: `remove_cron(id)`/`remove_timer(id)` before adding,
  and remove a previous driver instance before `add_driver`.

## 16. Ship large static HTML/JS as a file inside the `.tapp`

A `.tapp` is a stored (uncompressed) ZIP with `autoexec.be`; other files in it
are readable via `open(tasmota.wd + "file.html")`. A 5 kB chart skeleton read
from such a file on each real page load (from `web_add_main_button()`) costs
heap only while the page is being sent — compared to §7/§8, where it lives
permanently as a literal or cached string. It also keeps HTML/JS editable as a
normal file instead of an escaped one-line Berry string (Berry has no
multi-line string literals).

**Gotcha**: `tasmota.wd` is set **only while the `.tapp` is loading**
(`tasmota_class.be:load()` resets it to `""` afterwards). Capture it at load
time in a global: `var MYAPP_WD = tasmota.wd`.
