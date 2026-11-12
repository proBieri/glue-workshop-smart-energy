# Config file, sensor values, units, staleness

Part of the skill `tasmota-lowmem-webui` — read only the section you need.

## 9. No-reflash config via a small JSON file, not a config UI

For a handful of optional settings, skip building a settings UI/HTTP
handler - read a JSON file from the device filesystem once at boot, editable
through Tasmota's own built-in file manager (Werkzeuge -> Dateisystem
verwalten -> Neue Datei / Datei bearbeiten). No `persist` module needed:

```berry
var my_setting = false   # default

def load_config()
  try
    var f = open("myapp.cfg", "r")
    if f == nil return end
    var cfg = json.load(f.read())
    f.close()
    if cfg == nil return end
    var v = cfg.find("my_setting")
    # NOT bool(v) - Berry's bool() treats ANY non-empty string as true,
    # including the string "false". A hand-edited JSON file WILL eventually
    # contain a string where a real bool was meant. Compare explicitly:
    if v != nil my_setting = (v == true || v == 1) end
  except .. as e, m
    # missing/unreadable/corrupt file -> keep defaults, never crash
  end
end
```

Missing file, unreadable file, and malformed JSON must all silently fall
back to defaults - never let an optional config file crash the app.
Document that changes only take effect after a restart (the file is read
once at boot) unless you specifically build re-read-on-demand.

## 10. Don't trust a self-reported unit/scale label - cross-validate it

Whenever you're parsing a vendor/user-editable config that declares a unit
or scale for a value the raw payload doesn't carry (e.g. "this sensor field
is in kW" declared once in a separate config line, while the live JSON just
gives you a bare number) - the declared label can simply be wrong (a typo,
a copy-paste error from another line). If you have an independent way to
derive the same scale from physics/math, compute both and prefer the
independently-derived one on disagreement, with a logged warning:

```
declared unit -> scale A (from a human-edited text label)
apparent_va / raw_value -> scale B (from actual measurements: V x I vs raw power)
scale A == scale B -> confirmed, use it
scale A != scale B -> use B, but log a warning naming the likely-wrong field
```

Real example: a device's config declared `kW` for an aggregate power field
and `W` for the equivalent per-phase fields, using the identical underlying
multiplier - both could not be right simultaneously, and the per-phase
label was the wrong one. A physical cross-check (V×I apparent power vs. the
raw phase value) caught the 1000x error the label alone could not.

## 11. Freshness/staleness detection needs a signal that actually varies

If "has this sensor gone stale" is decided by fingerprinting a subset of
fields and checking whether the fingerprint changed within N seconds, that
fingerprint **must** be built from fields that are guaranteed to vary
whenever the device is genuinely alive - not just the fields you assume are
always present. A device variant that structurally lacks one of your chosen
fields (always reports 0 for it) will have a fingerprint that never changes,
and gets marked permanently stale/offline even while everything else is
updating normally. Include every field that can independently signal
freshness (raw power values, monotonically-increasing counters, etc.), not
just the first one that came to mind.

## 17. Numbers from sensor JSON: parse integers from text

Berry on the ESP32 uses 32-bit `int` and 32-bit `float` (~7 significant
digits). A meter reading of `7654.321` kWh × 1000 is already off by ±1 Wh, and
larger meters get worse. For counters, cut the number out of the
`tasmota.read_sensors()` text and build the integer directly
(`"Eo":234.567` → `234 * 1000 + 567` Wh). Also avoid `json.load()` on the full
sensor JSON when you only need two fields.
