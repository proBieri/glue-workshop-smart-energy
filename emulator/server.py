#!/usr/bin/env python3
"""gPlug-Emulator: Web-Server, der eine Tasmota-Hauptseite nachbildet und die
Berry-App in einem Berry-Prozess (emulator/runner.be) ausführt.

  http://localhost:8080/       Tasmota-Hauptseite (wie auf dem gPlug)
  http://localhost:8080/emu    Bedienfeld: Uhr, Zeitraffer, Zähler, Konsole, Log, Dateien
  http://localhost:8080/cm?cmnd=GplugInfo   Befehle wie auf dem Gerät

Umgebungsvariablen:
  GPLUG_SRC    Quellverzeichnis für "Neu bauen" (Standard: gplug)
  GPLUG_BUILD  Build-Verzeichnis (Standard: build) → GPLUG_BUILD/autoexec.be
  BKW_MODE     auto | live | fixture | error (Standard: auto)
  PORT         Standard: 8080
"""

import collections
import json
import os
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from quelle import Quelle   # Fehlerstellen autoexec.be:N → gplug/datei.be:M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

SRC = os.environ.get("GPLUG_SRC", "gplug")
BUILD = os.environ.get("GPLUG_BUILD", "build")
APP = os.path.join(BUILD, "autoexec.be")
QUELLE = Quelle(APP)
# eigenes Dateisystem pro Build, damit eigene App und Referenz parallel laufen können
FS = os.environ.get("GPLUG_FS") or os.path.join(
    "emulator", "fs" if os.path.normpath(BUILD) == "build" else "fs-" + os.path.basename(os.path.normpath(BUILD)))
PORT = int(os.environ.get("PORT", "8080"))
WEB = os.path.join("emulator", "web")


class Log:
    def __init__(self):
        self.lines = collections.deque(maxlen=3000)
        self.seq = 0
        self.lock = threading.Lock()

    def add(self, text):
        with self.lock:
            for line in str(text).rstrip("\n").split("\n"):
                self.seq += 1
                self.lines.append((self.seq, line))
        print(text, flush=True)

    def since(self, seq):
        with self.lock:
            return [{"n": n, "t": t} for n, t in self.lines if n > seq]


log = Log()


class Berry:
    """Ein Berry-Prozess mit der App; Anfragen laufen strikt nacheinander."""

    def __init__(self):
        self.proc = None
        self.lock = threading.RLock()
        self.fetch_mode = os.environ.get("BKW_MODE", "auto")
        self.speed = 1
        self.utc = int(time.time())
        self.meter = None
        self.load_ok = False
        self.berry_mode = None
        self.gen = 0          # zählt App-Starts; die Tasmota-Seite lädt sich bei Änderung neu

    def start(self, utc=None, meter=None):
        self.stop()
        os.makedirs(FS, exist_ok=True)
        if utc is not None:
            self.utc = utc
        cmd = ["stdbuf", "-oL", "berry", "-m", "emulator/mock", "emulator/runner.be",
               "emulator/mock", APP, FS, str(self.utc)]
        log.add(f"EMU: Starte Berry ({APP}, Uhr {time.strftime('%Y-%m-%d %H:%M', time.gmtime(self.utc))} UTC)")
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.berry_mode = None
        self.gen += 1
        ready = self._read_reply()
        self.load_ok = bool(ready and ready.get("load_ok"))
        if meter:
            self.request({"op": "meter", "ei_wh": meter["ei_wh"], "eo_wh": meter["eo_wh"],
                          "enabled": meter["enabled"], "pv_peak": meter["pv_peak"]})
        self.sync_fetch_mode()

    def stop(self):
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.stdin.write('{"op":"quit"}\n')
                self.proc.stdin.flush()
                self.proc.wait(timeout=2)
            except Exception:
                self.proc.kill()
        self.proc = None

    def _read_reply(self):
        while True:
            line = self.proc.stdout.readline()
            if line == "":
                log.add("EMU: Berry-Prozess beendet (Absturz?) — im Bedienfeld neu starten")
                return None
            line = line.rstrip("\n")
            if line.startswith("\x01"):
                return json.loads(line[1:])
            if line.startswith("\x02FETCH "):
                self._fetch(json.loads(line[7:]))
                continue
            line = QUELLE.zeile(line)
            if line is not None:
                log.add(line)

    def _fetch(self, req):
        reply = {"code": -1}
        try:
            r = urllib.request.Request(req["url"], method=req.get("method", "GET"),
                                       data=(req.get("payload") or "").encode() or None,
                                       headers=req.get("headers") or {})
            with urllib.request.urlopen(r, timeout=15) as resp:
                body = resp.read()
                reply["code"] = resp.status
        except urllib.error.HTTPError as e:
            body = e.read()
            reply["code"] = e.code
        except Exception as e:
            log.add(f"EMU: Abruf fehlgeschlagen: {e}")
            body = b""
        fd, path = tempfile.mkstemp(prefix="fetch_", dir="/tmp")
        with os.fdopen(fd, "wb") as f:
            f.write(body)
        reply["file"] = path
        self.proc.stdin.write(json.dumps(reply) + "\n")
        self.proc.stdin.flush()

    def request(self, obj):
        with self.lock:
            if not self.proc or self.proc.poll() is not None:
                return {"error": "Berry läuft nicht"}
            try:
                self.proc.stdin.write(json.dumps(obj) + "\n")
                self.proc.stdin.flush()
            except BrokenPipeError:
                return {"error": "Berry läuft nicht"}
            r = self._read_reply()
            if r is None:
                return {"error": "Berry-Prozess beendet"}
            if "utc" in r and obj.get("op") == "tick":
                self.utc = r["utc"]
            return r

    def sync_fetch_mode(self, jump=False):
        mode = self.fetch_mode
        if mode == "auto":
            live = abs(self.utc - time.time()) < 120 and self.speed == 1 and not jump
            mode = "proxy" if live else "fixture"
        elif mode == "live":
            mode = "proxy"
        if mode != self.berry_mode:
            self.request({"op": "config", "fetch_mode": mode})
            self.berry_mode = mode
            log.add(f"EMU: BKW-API-Modus: {mode}")

    def advance(self, ms):
        self.sync_fetch_mode(jump=ms > 5000)
        return self.request({"op": "tick", "ms": int(ms)})

    def restart(self, reset=False):
        with self.lock:
            self._restart(reset)

    def _restart(self, reset):
        st = self.request({"op": "state"})
        meter = st.get("meter") if isinstance(st, dict) else None
        if not reset:
            self.request({"op": "restart"})
        utc = self.utc
        if reset:
            for f in os.listdir(FS) if os.path.isdir(FS) else []:
                os.remove(os.path.join(FS, f))
            utc = int(time.time())
            self.speed = 1
            meter = None
            log.add("EMU: Dateisystem geleert, Uhr auf Echtzeit")
        self.start(utc, meter)


berry = Berry()


def app_mtime():
    try:
        return os.path.getmtime(APP)
    except OSError:
        return 0


app_geladen = 0      # mtime der zuletzt geladenen autoexec.be


def build_fertig(ruhe):
    """build.sh ist durch: gplug.tapp (Schritt 4) neuer als autoexec.be und seit `ruhe` s unverändert."""
    try:
        t = os.path.getmtime(os.path.join(os.path.dirname(APP), "gplug.tapp"))
    except OSError:
        return False
    return t >= app_mtime() and time.time() - t >= ruhe


def laden(grund):
    """App neu laden; gibt {ok, log} zurück (Log-Zeilen des Ladens)."""
    global app_geladen
    app_geladen = app_mtime()
    n = log.seq
    log.add(f"EMU: {grund} — lade App neu")
    berry.restart()
    return {"ok": berry.load_ok, "log": [z["t"] for z in log.since(n)]}


def clock():
    global app_geladen
    last = time.time()
    app_geladen = app_mtime()
    while True:
        time.sleep(1)
        now = time.time()
        dt = now - last
        last = now
        # neu gebaut, aber nicht über /emu/api/laden gemeldet? → App neu laden.
        # Erst wenn build.sh fertig ist (gplug.tapp neuer als autoexec.be, seit 3 s):
        # vorher fehlen Dateien (build.sh leert das Verzeichnis), und build.sh meldet
        # den Build ohnehin selbst über /emu/api/laden.
        if app_mtime() != app_geladen and build_fertig(3):
            laden(f"{APP} wurde neu gebaut")
            continue
        if berry.speed > 0 and berry.proc:
            berry.advance(dt * 1000 * berry.speed)


def build():
    log.add(f"EMU: bash build.sh {SRC} {BUILD}")
    p = subprocess.run(["bash", "build.sh", SRC, BUILD], capture_output=True, text=True)
    log.add((p.stdout + p.stderr).rstrip())
    return p.returncode == 0


# Tasmota-Hauptseite (vereinfacht, gleiche Mechanik: #l1 wird per /?m=1 ersetzt)
MAIN = """<!DOCTYPE html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<title>gPlug - Hauptmenü</title>
<script>
var x=null,lt,to,tp,pc='';var sn=0,id=0,ft,ltm=2345;
function eb(s){return document.getElementById(s);}
function la(p){a=p||'';clearTimeout(ft);clearTimeout(lt);if(x!=null){x.abort()}x=new XMLHttpRequest();
x.onreadystatechange=()=>{if(x.readyState==4&&x.status==200){var s=x.responseText.replace(/{t}/g,"<table style='width:100%'>")
.replace(/{s}/g,"<tr><th>").replace(/{m}/g,"</th><td style='width:20px;white-space:nowrap'>").replace(/{e}/g,"</td></tr>");
eb('l1').innerHTML=s;clearTimeout(ft);clearTimeout(lt);lt=setTimeout(la,ltm);}};
x.open('GET','.?m=1'+a,true);x.send();ft=setTimeout(la,2e4);}
window.onload=function(){la();emu();};
/* Nur im Emulator: Seite neu laden, wenn die App neu gestartet wurde (neuer Build)
   oder die virtuelle Uhr eine neue Stunde erreicht (Zeitraffer) — höchstens alle 5 s.
   Auf dem Gerät gibt es das nicht: dort lädt man die Seite selbst neu. */
/* eg = App-Start, der DIESE Seite erzeugt hat (vom Server eingesetzt) — nicht der beim
   ersten Abfragen; sonst bleibt eine Seite aus einem Zwischenstart stehen. */
var eg=%GEN%,eh=null,et=Date.now();
function emu(){fetch('/emu/api/gen').then(function(r){return r.json();}).then(function(s){
  if(eh===null)eh=s.hour;
  if(s.gen!==eg||(s.hour!==eh&&Date.now()-et>5000)){location.reload();return;}
}).catch(function(){}).then(function(){setTimeout(emu,2000);});}
</script>
<style>
div,fieldset,input,select{padding:5px;font-size:1em}p{margin:.5em 0}
body{text-align:center;font-family:verdana,sans-serif;background:#252525;color:#eaeaea}
td{padding:0}th{text-align:left;font-weight:normal}
button{border:0;border-radius:.3rem;background:#1fa3ec;color:#faffff;line-height:2.4rem;font-size:1.2rem;width:100%;cursor:pointer}
button:hover{background:#0e70a4}a{color:#1fa3ec;text-decoration:none}
</style></head><body>
<div style='text-align:left;display:inline-block;color:#eaeaea;min-width:340px;max-width:420px'>
<div style='text-align:center;color:#eaeaea'><noscript>JavaScript aktivieren<br></noscript>
<h3>gPlug Emulator</h3><h2>gPlug</h2></div>
<div style='padding:0' id='l1' name='l1'></div><div></div>
%MAIN%
<p></p><form action='/emu' method='get' target='_top'><button>Emulator-Bedienfeld</button></form>
<div style='text-align:right;font-size:11px'><hr><a href='https://tasmota.github.io' target='_blank' style='color:#aaa'>Tasmota 15.3.0 (Emulator)</a></div>
</div></body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "gPlugEmu/1.0"

    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, mime="text/html; charset=utf-8", headers=None):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def json(self, obj, code=200):
        self.send(code, json.dumps(obj), "application/json")

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n).decode() if n else ""

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query, keep_blank_values=True).items()}
        p = u.path

        if p in ("/", "/index.html"):
            if "m" in q:
                r = berry.request({"op": "sensor", "args": q})
                return self.send(200, "{t}" + r.get("html", "") + "</table>")
            with berry.lock:                     # Seite und App-Start gehören zusammen
                r = berry.request({"op": "main", "args": q})
                gen = berry.gen
                ok = berry.load_ok
            html = r.get("html", "") if ok else \
                "<p style='color:#f66'>App nicht geladen — Fehler im Log (Bedienfeld)</p>"
            return self.send(200, MAIN.replace("%MAIN%", html).replace("%GEN%", str(gen)))
        if p == "/cm":
            r = berry.request({"op": "cmd", "line": q.get("cmnd", "")})
            if r.get("restart"):
                threading.Thread(target=berry.restart, daemon=True).start()
            return self.send(200, r.get("resp", json.dumps(r)), "application/json")
        if p in ("/emu", "/emu/"):
            with open(os.path.join(WEB, "emu.html"), encoding="utf-8") as f:
                return self.send(200, f.read())
        if p == "/emu/api/state":
            st = berry.request({"op": "state"})
            st.update({"speed": berry.speed, "bkw_mode": berry.fetch_mode, "app": APP, "src": SRC,
                       "load_ok": berry.load_ok, "real_utc": int(time.time())})
            return self.json(st)
        if p == "/emu/api/gen":
            return self.json({"gen": berry.gen, "hour": (berry.utc + 3600) // 3600})
        if p == "/emu/api/log":
            return self.json(log.since(int(q.get("seit", "0"))))
        if p == "/emu/api/files":
            files = []
            if os.path.isdir(FS):
                for f in sorted(os.listdir(FS)):
                    files.append({"name": f, "size": os.path.getsize(os.path.join(FS, f))})
            return self.json(files)
        if p.startswith("/emu/fs/"):
            name = os.path.basename(urllib.parse.unquote(p[8:]))
            path = os.path.join(FS, name)
            if not os.path.isfile(path):
                return self.send(404, "fehlt", "text/plain")
            with open(path, "rb") as f:
                mime = "text/csv; charset=utf-8" if name.endswith(".csv") else "text/plain; charset=utf-8"
                return self.send(200, f.read(), mime)
        r = berry.request({"op": "http", "path": p, "method": "GET", "args": q})
        mime = r.get("mime") or "text/html"
        if mime.startswith("text/") and "charset" not in mime:
            mime += "; charset=utf-8"
        return self.send(r.get("code", 500), r.get("body", ""), mime)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        p = u.path
        if p.startswith("/emu/fs/"):
            name = os.path.basename(urllib.parse.unquote(p[8:]))
            with open(os.path.join(FS, name), "w", encoding="utf-8") as f:
                f.write(self.body())
            log.add(f"EMU: Datei /{name} gespeichert (wirkt nach Neustart der App)")
            return self.json({"ok": True})
        if not p.startswith("/emu/api/"):
            r = berry.request({"op": "http", "path": p, "method": "POST", "args": {}})
            return self.send(r.get("code", 500), r.get("body", ""), r.get("mime") or "text/html")
        try:
            a = json.loads(self.body() or "{}")
        except ValueError:
            a = {}
        act = p[9:]
        if act == "speed":
            berry.speed = max(0, int(a.get("speed", 1)))
            berry.sync_fetch_mode()
            return self.json({"speed": berry.speed})
        if act == "advance":
            return self.json(berry.advance(int(a.get("s", 0)) * 1000))
        if act == "meter":
            return self.json(berry.request(dict(a, op="meter")))
        if act == "bkw":
            berry.fetch_mode = a.get("mode", "auto")
            berry.sync_fetch_mode()
            return self.json({"bkw_mode": berry.fetch_mode})
        if act == "cmd":
            r = berry.request({"op": "cmd", "line": a.get("line", "")})
            log.add(f"CMD: {a.get('line', '')} → {r.get('resp', r)}")
            if r.get("restart"):
                threading.Thread(target=berry.restart, daemon=True).start()
            return self.json(r)
        if act == "restart":
            berry.restart()
            return self.json({"ok": berry.load_ok})
        if act == "reset":
            berry.restart(reset=True)
            return self.json({"ok": berry.load_ok})
        if act == "laden":                       # von build.sh nach jedem Build
            if os.path.normpath(a.get("build", "")) != os.path.normpath(BUILD):
                return self.json({"ok": None, "build": BUILD})
            return self.json(laden(f"build.sh hat {APP} gebaut"))
        if act == "build":
            ok = build()                          # Neuladen übernimmt clock() (neue autoexec.be)
            return self.json({"ok": ok})
        return self.json({"error": "unbekannt"}, 404)


def main():
    if not os.path.exists(APP):
        log.add(f"EMU: {APP} fehlt — baue {SRC}")
        build()
    berry.start(int(time.time()))
    threading.Thread(target=clock, daemon=True).start()
    log.add(f"EMU: bereit — http://localhost:{PORT}/emu (Tasmota-Seite: http://localhost:{PORT}/)")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
