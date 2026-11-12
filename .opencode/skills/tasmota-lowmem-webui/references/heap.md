# Heap: storage, literals, memoizing, diagnosis

Part of the skill `tasmota-lowmem-webui` — read only the section you need.

## 6. Heap-conscious storage: `bytes()` ring buffers, not lists

For a fixed-size numeric time series (e.g. a sampled value every N seconds
for an hour), use a single `bytes()` object with a fixed per-sample width
instead of a Berry `list` of boxed values - far less heap on a no-PSRAM
target:

```berry
class RingBuffer
  var buf, head, count
  def init(len)
    self.buf = bytes(-len * 2)   # 16-bit signed per sample
    self.head = 0
    self.count = 0
  end
  def push(value)
    if value == nil return end               # skip ticks with no data - don't fill gaps with 0
    var v = int(value)
    if v > 32767 v = 32767 end
    if v < -32768 v = -32768 end
    self.buf.set(self.head * 2, v & 0xFFFF, 2)
    self.head = (self.head + 1) % size(self.buf, 0)
  end
end
```

**Gotcha**: `.get()` on a `bytes()` buffer returns unsigned - decode signed
16-bit manually (`raw >= 32768 ? raw - 65536 : raw`). And return the decoded
value as a **float**, not an int, if any downstream math divides by a span
derived from it - Berry is dynamically typed, so the moment an `int` value
overwrites a running `min`/`max` that started as `0.0`, subsequent division
silently becomes truncating integer division instead of float division.
(Symptom on real hardware: every chart point but the exact extreme value
collapsed to the same spot.)

## 7. Memoize static HTML - but know the tradeoff

If a skeleton (or any other "always identical, computed from constants
only") string gets rebuilt via many small `tasmota.web_send()` /
`string.format()` calls, and something still calls that render path more
than once per boot (e.g. multiple real page loads), build it into a string
once and cache it in a global instead of re-running the builder every time:

```berry
var _skeleton_html = nil
def get_skeleton_html()
  if _skeleton_html == nil
    _skeleton_html = build_skeleton()   # was: many web_send() calls; now: one cached string
  end
  return _skeleton_html
end
```

This trades a small **permanent** heap cost (the cached string lives for the
life of the process) for eliminating repeated string-concatenation garbage
on every call. Worth it when the render path fires often (e.g. was
previously wired to `web_sensor()`'s every-2-3s poll, per §1); not worth
doing pre-emptively for something that only ever renders once anyway.

## 8. Merge adjacent pure-text string literals - each one is a permanent heap object

Separately from *how often* a string gets built (§7), *how many source-level
literals* it's built from has its own, independent heap cost. Splitting
static text across many small literals joined by `+` - purely for source
readability, one JS/CSS line per Berry string - is common and looks free,
but is not:

- Berry's compiler does **not** constant-fold literal-to-literal
  concatenation. Verified with a controlled test on the desktop Berry CLI:
  100 distinct 10-byte literals joined by `+` compiled to a 1749-byte
  `.bec`; the identical total text as **one** literal compiled to 1060 bytes
  - a 39% difference for the exact same output.
- Every literal becomes its own heap-resident constant object, retained for
  as long as the enclosing function/closure stays loaded - which, for a
  top-level `def` executed via Tasmota's non-module-isolated `load()`, is
  the life of the process. This is **not garbage-collectible content**: it
  isn't leftover garbage from a call that already returned, it's part of
  the function's permanent constant pool. Forcing `tasmota.gc()` will not
  reduce it (see §10's leak-vs-fixed-cost check).

**The fix**: wherever two or more string literals sit adjacent with **no
Berry variable/expression between them** (a pure run of static text, e.g. a
`<style>` block or a client-side `<script>` built from many `"..."+"..."+...`
JS-source fragments), merge them into one literal. Where a real variable
*does* sit between two fragments (a color constant, a computed number),
leave that split in place - only the runs of pure adjacent text are free
wins. On a real ~2200-line driver, merging the two most fragmented functions
(a ~20-fragment CSS block and a ~45-fragment client-JS block, both 100%
static, zero variables) cut compiled size by only ~1.3% - modest, because
most of the rest of a typical driver's code legitimately interleaves
literals with real data and has nothing further to merge. Verify equivalence
before/after with the isolated-function CLI technique in §10, not by eye -
manually reassembling a long escaped string by hand is error-prone; do it
with a small script that tokenizes and rejoins the literals instead of
retyping them.

## 12. Diagnosing Berry heap growth, and telling "my code" from "the whole device"

- `tasmota.memory()` via the Berry console (`BR tasmota.memory()`, or
  `http://device/cm?cmnd=BR%20tasmota.memory()`) returns a map including
  `gc_heap` (Berry's own heap usage, KB), `heap_free`, and `frag`
  (fragmentation %). This is a different pool from Tasmota's general
  "Freier Arbeitsspeicher" on the Information page, and different again from
  `Status 11`'s `Heap`/`Berry.HeapUsed`/`Berry.Objects` (whole-VM totals
  across *every* loaded script, not just yours) - don't conflate any of
  these three.
- Force a collection with `tasmota.gc()` and re-check `gc_heap`/`Berry.*`.
  If it drops a lot, you had accumulated garbage. If it **doesn't move at
  all** - even measured seconds after boot vs. hours later, both right after
  a forced GC - the reported usage is genuinely permanent/retained: either a
  cache (§7) or the fixed cost of the code itself being loaded (§8), not a
  leak. A real leak keeps climbing release-over-release or hour-over-hour
  even with GC forced each time; a fixed cost is flat from shortly after
  boot onward.
- To separate "more code" from "a leak" across versions, compare compiled
  `.bec` size between the old and new source as a cheap proxy for
  code-driven heap growth (`compile_to_bec.be` in a desktop Berry CLI built
  from the exact Tasmota Berry source tag - see the project's own
  `build_berry_cli.sh` if present). A `.bec` size delta roughly proportional
  to the heap delta suggests "more functions/features" (or §8's literal
  fragmentation), not a leak; a heap delta far exceeding the `.bec` delta
  warrants looking for a growing cache or an uncapped data structure
  instead. The same desktop CLI is also the fastest way to verify a
  refactor is behavior-neutral: extract just the changed function (old
  version vs. new) into a standalone script ending in `print(the_expression)`
  and diff the two outputs, rather than trusting a read-through of a long
  merged string.
- **Isolate "is my endpoint slow" from "is the whole device slow"** before
  optimizing your own handler's computation: time a request to your handler,
  then *also* time a request to something totally unrelated and stock (e.g.
  `Status 0`, or even a 404 for a nonexistent file) at the same session. If
  the unrelated request is comparably slow, the bottleneck is device-wide
  (WiFi signal quality, a VPN tunnel's crypto overhead, other Berry
  drivers/scripts sharing the single-threaded event loop) - no amount of
  optimizing your own JSON-building code will fix that. Cross-check with
  `Status 11`'s `LoadAvg`: low LoadAvg + uniformly high latency across
  unrelated requests points at network/transport, not CPU; elevated LoadAvg
  points at the main loop itself being busy. **Let LoadAvg settle after a
  reboot before trusting it** - WiFi/MQTT/VPN reconnection produces a
  transient spike for the first ~1-2 minutes after boot; comparing a
  freshly-booted reading against a long-uptime one (or vice versa) will
  misattribute that boot noise to whatever you actually changed.
- **Isolating one driver's own share of a shared device**: if several
  independent scripts/`.tapp`s are loaded on the same device, temporarily
  remove the one you're investigating (`UfsDelete`), restart, force
  `tasmota.gc()`, and read `Status 11`/`tasmota.memory()` as your baseline;
  restore the file (re-upload, or keep a byte-identical local copy - a
  build script's own last output is often exactly that), restart, and
  measure again the same way. This is the only reliable way to attribute
  heap/LoadAvg cost to one specific driver when Tasmota's own totals are
  necessarily whole-VM.
