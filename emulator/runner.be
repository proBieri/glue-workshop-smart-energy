# runner.be — Berry-Seite des Emulators
#
# Aufruf (macht server.py):
#   berry -m emulator/mock emulator/runner.be <mock_dir> <app.be> <fs_dir> <utc>
#
# Protokoll über stdin/stdout, eine Zeile JSON pro Anfrage:
#   Anfrage  -> {"op": "...", ...}
#   Antwort  <- "\x01" + JSON          (genau eine pro Anfrage)
#   Abruf    <- "\x02FETCH " + JSON     (webclient im Proxy-Modus, Antwort per stdin)
#   alles andere auf stdout ist Log-Ausgabe der App (print, log, Exceptions)

import json
import string

var _mock_dir = _argv[1]
var _app = _argv[2]
# vom Emulator (emu.be) zur Laufzeit gesetzte Globals — vorher deklarieren,
# weil Berry beim Kompilieren jeden Namen kennen muss
var _emu, _emu_fopen, _emu_days_from_civil, _emu_time_dump, _emu_tz_offset, _emu_bkw_fixture, gc
compile(_mock_dir + "/emu.be", "file")()
_emu.fs_root = _argv[3]
_emu.set_clock(int(_argv[4]))

def _reply(m) print("\x01" + json.dump(m)) end

def _state()
  var crons = []
  for c: _emu.crons crons.push([str(c[2]), c[0]]) end
  var routes = []
  for r: _emu.routes routes.push(r[0]) end
  var cmds = []
  for k: _emu.cmds.keys() cmds.push(k) end
  var m = _emu.meter
  return {'utc': _emu.utc, 'local': _emu.local(), 'tz': _emu.tz(), 'uptime': _emu.utc - _emu.boot_utc,
          'heap': gc.allocated(), 'fetch_mode': _emu.fetch_mode, 'fetch_count': _emu.fetch_count,
          'drivers': size(_emu.drivers), 'crons': crons, 'timers': size(_emu.timers),
          'routes': routes, 'cmds': cmds,
          'meter': {'enabled': m.enabled, 'ei_wh': m.ei_wh, 'eo_wh': m.eo_wh, 'pi': m.pi, 'po': m.po, 'pv_peak': m.pv_peak}}
end

def _web(event, args)
  _emu.web_out = []
  _emu.req_args = args != nil ? args : {}
  _emu.dispatch(event)
  return _emu.web_out.concat()
end

def _http(path, method, args)
  var mcode = method == "POST" ? 3 : 1
  for r: _emu.routes
    if r[0] == path && (r[2] == 0 || r[2] == mcode)
      _emu.web_out = []
      _emu.web_code = 200
      _emu.web_mime = "text/html"
      _emu.req_args = args != nil ? args : {}
      _emu.call_safe(r[1], "webserver " + path)
      return {'code': _emu.web_code, 'mime': _emu.web_mime, 'body': _emu.web_out.concat()}
    end
  end
  return {'code': 404, 'mime': 'text/plain', 'body': 'Nicht gefunden: ' + path}
end

def _handle(req)
  var op = req['op']
  if op == "tick"
    _emu.advance(int(req['ms']))
    return {'utc': _emu.utc, 'local': _emu.local()}
  elif op == "state"
    return _state()
  elif op == "main"
    return {'html': _web("web_add_main_button", req.find('args'))}
  elif op == "sensor"
    return {'html': _web("web_sensor", req.find('args'))}
  elif op == "http"
    return _http(req['path'], req.find('method', 'GET'), req.find('args'))
  elif op == "cmd"
    var r = _emu.exec_cmd(req['line'])
    return {'resp': r, 'restart': _emu.restart_requested}
  elif op == "meter"
    var m = _emu.meter
    if req.contains('enabled') m.enabled = req['enabled'] end
    if req.contains('pv_peak') m.pv_peak = int(req['pv_peak']) end
    if req.contains('ei_wh') m.ei_wh = int(req['ei_wh']) end
    if req.contains('eo_wh') m.eo_wh = int(req['eo_wh']) end
    return _state()['meter']
  elif op == "config"
    if req.contains('fetch_mode') _emu.fetch_mode = req['fetch_mode'] end
    return {'fetch_mode': _emu.fetch_mode}
  elif op == "restart"
    _emu.dispatch("save_before_restart")
    import persist
    persist.save()
    return {'ok': true}
  end
  return {'error': 'unbekannte Operation: ' + str(op)}
end

# --- App laden wie Tasmota eine .tapp beim Booten ---
# tasmota.wd ist nur während des Ladens gesetzt (wie tasmota_class.be:load)
var _load_ok = _emu.load_app(_app)
_emu.dispatch("autoexec")
_emu.dispatch("web_add_handler")
_reply({'ready': true, 'load_ok': _load_ok})

while true
  var line = input()
  if line == nil || line == "" break end
  var req
  try
    req = json.load(line)
  except ..
    req = nil
  end
  if req == nil || type(req) != 'instance'
    _reply({'error': 'ungültige Anfrage'})
    continue
  end
  if req['op'] == "quit" break end
  try
    _reply(_handle(req))
  except .. as e, m
    _reply({'error': str(e) + ": " + str(m)})
  end
end
