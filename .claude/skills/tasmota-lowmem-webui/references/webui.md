# WebUI: hooks, data delivery, chart payloads

Part of the skill `tasmota-lowmem-webui` — read only the section you need.

## 1. Know which hook you're in - it changes everything

Tasmota calls two different driver hooks for web-UI content, and they behave
completely differently:

- **`web_sensor()`** fires on **every** periodic sensor poll (Tasmota's
  built-in `/?m=1` AJAX refresh, roughly every 2-3s) - AND that poll
  **replaces the entire sensor container's `innerHTML`** each time, wiping
  out anything that lived inside it (including stuff placed there via other
  means).
- **`web_add_main_button()`** fires **once**, only as part of a real page
  load of `/` - verified on real hardware: its output appears in `/` but
  never in `/?m=1`. It does NOT re-fire on the periodic poll.

**The trap**: putting anything non-trivial in `web_sensor()` means it gets
regenerated and retransmitted on *every single poll*, forever, even if the
content never changes. A static SVG skeleton, a `<style>` block, chart
scaffolding - none of that needs to be sent more than once, but
`web_sensor()` will send it every 2-3 seconds anyway.

**The fix**: render one-time/static content from `web_add_main_button()`
instead. If you need it positioned at a specific spot in the page (e.g. "at
the top", ahead of Tasmota's own sensor table), don't fight it with CSS
flex/order tricks on the polled container - **relocate the DOM node itself**
so it's no longer inside the container that gets wiped:

```js
// emitted once from web_add_main_button(), as part of the real page load
(function(){
  var w = document.getElementById('my_widget'); // rendered with style="display:none"
  var l1 = document.getElementById('l1');        // Tasmota's polled sensor container
  if (w && l1 && l1.parentNode) l1.parentNode.insertBefore(w, l1); // sibling, not child
  if (w) w.style.display = '';
})();
```

Once your widget is a **sibling** of the polled container instead of a
*child*, Tasmota's periodic replace never touches it again - your static
markup is transmitted exactly once per real page load, not once per poll.
This also eliminates any need for the *old-style* MutationObserver hack of
reapplying your data after Tasmota wipes it - there's nothing to reapply if
your widget is never wiped. (§3 below reintroduces a MutationObserver for a
different, narrower purpose - know the two are not the same trick.)

`web_sensor()` can then be left undefined entirely if you have nothing that
truly needs to live inside the polled table - or repurposed per §3.

## 2. Split skeleton from data, and poll the data independently

Once static markup escapes the poll cycle (§1), the remaining problem is
*values that do change*. Don't regenerate the whole HTML fragment to update
them - split rendering into two pieces:

1. **Skeleton** (rendered once): the fixed structure - SVG shapes, empty
   `<text>`/`<polyline>` elements carrying `id="..."` attributes, `<style>`.
   Content-free placeholders, identical on every real page load.
2. **Data endpoint**: register a lightweight JSON handler -
   `webserver.on("/mydriver.json", handler, webserver.HTTP_GET)` inside
   `web_add_handler()` (fires once at boot) - that returns just the values,
   nothing else. Poll it from client JS on your own timer:

```js
function update(){
  fetch('mydriver.json').then(r=>r.json()).then(d=>{
    document.getElementById('val').textContent = d.v;
    document.getElementById('arc').setAttribute('d', d.d);
  }).catch(()=>{});
}
update(); setInterval(update, 10000);
```

Use a **relative** fetch path (`'mydriver.json'`, no leading `/`) rather than
an absolute one - it resolves against the current page URL, which still
works if the device is reverse-proxied under a sub-path (`/gplug/` etc.);
an absolute `/mydriver.json` bypasses the proxy prefix and 404s.

Keep the JSON payload itself compact: short keys (`"v"` not `"value"`),
arrays instead of named sub-objects where the order is fixed and documented,
and don't repeat text the skeleton already has (a static label doesn't need
to come back over the wire every poll).

This gives your data its own poll cadence, fully decoupled from Tasmota's
native one - useful when you deliberately want to poll *less* often than
Tasmota does. See §3 for the alternative when that decoupling itself becomes
the problem.

## 3. Or: embed data in `web_sensor()` with a MutationObserver as a pure trigger

§2's independent endpoint has two costs that only show up once you're
running it in production over a real, imperfect link: (a) it is a **second
full HTTP request** every cycle, on top of Tasmota's own native poll - and on
a loaded/slow device, request *count* can matter more than payload size,
because each request carries its own largely payload-size-independent
latency overhead (TCP/TLS-under-VPN setup, the device's single-threaded
webserver queueing behind whatever else is running) - see §10's "isolate
device-wide vs. app-specific" technique for how to confirm this on your own
device before assuming it; and (b) your widget's values and Tasmota's own
native sensor table are now on two **independent timers**, so they can
visibly disagree for a moment after a real value change (a customer will
notice this: "the number top-left doesn't match the table below it").

If you've already gotten the payload small (§4/§5 below) and want to fix
either of those, embed the same payload **inside** Tasmota's own poll
response instead of a separate endpoint - re-purposing `web_sensor()` (§1)
now that you have something worth putting there once per poll:

```berry
def web_sensor()
  var json_text = json.dump(build_payload())
  # Only '&' and the matching quote need escaping inside a single-quoted
  # HTML attribute value (not '<'/'>') - and getAttribute() on the client
  # automatically un-escapes them back, so no decode step is needed there.
  # (Base64, per §4, is still the right choice for genuine binary content -
  # this plain-text escape is for the JSON-as-text wrapper around it.)
  json_text = string.replace(json_text, "&", "&amp;")
  json_text = string.replace(json_text, "'", "&#39;")
  tasmota.web_send("<div id='mydata' style='display:none' data-v='" + json_text + "'></div>")
end
```

```js
// static widget script (from web_add_main_button(), fires once) -
// observe #l1 itself purely as a TRIGGER: every replace of its content
// means Tasmota just polled and re-rendered web_sensor(), so a fresh
// #mydata is now sitting inside it - no fetch() needed at all.
var l1 = document.getElementById('l1');
function update(){
  var e = document.getElementById('mydata');
  if (!e) return;
  try { applyData(JSON.parse(e.getAttribute('data-v'))); } catch(ex) {}
}
update();
if (l1 && window.MutationObserver) new MutationObserver(update).observe(l1, {childList:true});
setInterval(update, 15000); // fallback only, in case the observer never fires - it should dominate in normal operation
```

This `MutationObserver` is a **different use** than the one §1 eliminates: it
is not reapplying wiped-out widget content (the widget still lives outside
`#l1`, untouched, per §1) - it is purely a signal that says "Tasmota just
polled, go read the fresh data it just delivered." Only the small,
content-free `<div data-v='...'>` needs to live inside the polled container,
because it's *meant* to be replaced every cycle.

**Net effect**: one HTTP request per poll cycle instead of two, and your
widget and Tasmota's native table always render from the exact same
response - they cannot disagree. **Trade-off**: you lose independent control
of your own poll cadence - you now update exactly as often as Tasmota's
native sensor poll runs (typically every 2-3s, i.e. more often than most
`setInterval`-based §2 setups, so re-check §4's point cap against this new,
usually higher, frequency - the two settings interact).

## 4. Binary-encode numeric series instead of decimal text

If the data payload carries a chart/series of numbers (e.g. chart point
coordinates), decimal-text encoding is expensive: `"34,106 41,106 "` is
~7-8 bytes per point. Two changes cut that by 5-8x:

- **Drop reconstructable dimensions.** If X is evenly spaced (a fixed-width
  chart over N samples), don't send it - the client can recompute
  `x = left_pad + i * (chart_w / (n-1))` from the array length alone.
- **Send the remaining values as raw bytes, base64-encoded**, not as decimal
  text. Berry's `bytes` type has `.tob64()` built in - no extra module:

```berry
var buf = bytes(-n)              # n raw bytes
buf.set(i, clamp(y, 0, 255), 1)  # one byte per point, e.g. a pixel Y coord
return buf.tob64()               # -> compact base64 string for the JSON payload
```

```js
// client side - reverse of the above
function decode(b64, leftPad, chartW){
  var bin = atob(b64), n = bin.length;
  var step = n > 1 ? chartW / (n - 1) : 0, out = '';
  for (var k = 0; k < n; k++) out += (leftPad + k*step).toFixed(0)+','+bin.charCodeAt(k)+' ';
  return out;
}
```

This only works when each value fits in a byte (0-255) - fine for pixel
coordinates in a small chart, not for arbitrary raw sensor magnitudes.

## 5. Downsample with a point cap, and draw one shape

If a value history can grow (a ring buffer filling up over an hour), cap the
number of points actually *drawn*, independent of how many are *stored* -
sample evenly across the buffer rather than truncating to the most recent N.
And draw the whole series as **one** `<polyline points="...">`, never as one
`<line>`/element per segment - on a real device, rendering a full buffer as
individual line elements (hundreds of them, per series) was the likely root
cause of an observed instability/restart bug over a slow link: the resulting
HTML could exceed 100KB per render, in a payload the transport couldn't move
fast enough to keep up before the next poll fired.

**The cap's safe value depends on poll frequency, not just payload size** -
raising resolution (a bigger cap) and raising poll frequency (e.g. switching
from §2 to §3, or just shortening a §2 `setInterval`) multiply together. A
cap that was fine at "every 10s" can reproduce the original bandwidth problem
once the same payload goes out "every 2.5s" instead - re-validate the cap
whenever the polling mechanism changes, don't assume it still holds.

## 13. Move recurring per-poll *computation*, not just raw data, to the client

§3's client-side segmentation is one instance of a broader pattern worth
checking for systematically: anywhere a per-poll payload field is a
**derived/formatted** value (an SVG path string, a set of chosen axis
tick positions with formatted labels, a color decided by a threshold) built
from a couple of raw numbers already in scope server-side, consider sending
the smaller raw numbers instead and doing the derivation in client JS - a
browser's JS engine does trig/loops/string-building for free (relative to
the poll interval) while the same work on a no-PSRAM ESP32's Berry
interpreter is real, recurring per-poll cost.

Two concrete instances from the same driver, both moved client-side for a
combined win (less Berry work **and** smaller payload, not a size/CPU
trade-off):

- **A gauge needle's SVG arc path.** Building the path server-side needs 2
  calls into a polar-to-cartesian helper (`cos`/`sin` each) plus a
  `string.format()` producing a ~40-character path string
  (`"M78.5 15.2 A42.0 42.0 0 0 1 91.3 48.7"`). Sending just the two
  fraction-of-range endpoints (2 small floats) instead, and letting the
  client run the same trig (`Math.cos`/`Math.sin`, hardware-fast) with the
  gauge's geometry constants (center/radius) hardcoded to match the static
  skeleton, is both less Berry work and arguably fewer bytes.
- **Chart axis grid lines.** Choosing a "nice" step size from a short fixed
  list (so a large-range chart doesn't get illegibly dense fixed-500-unit
  gridlines) and formatting each line's pixel position + label
  (`"1.2k"`/`"500"`/`"0"`) server-side means sending up to
  `GD_TS_GRID_MAX_LINES` `[pixel, label]` pairs (up to ~150 bytes, plus a
  formatting loop, on the server) every poll. Sending just the series'
  `min`/`max` (2 floats) and replicating the tiny step-selection list and
  label-formatting logic in client JS instead cut this to 2 numbers, with
  the client already needing the same "value -> pixel" formula for the
  data points themselves (§4) - one shared helper covers both.

**The tell**: if you're about to `string.format()` something server-side
that's purely a presentation detail (a path, a label, a CSS value) computed
from numbers you could send instead, ask whether the client could compute
that presentation detail itself from smaller inputs. If yes, and the raw
inputs are no bigger than the formatted output, moving it is close to
free - not a trade-off like §5's resolution-vs-bandwidth choice.
