# webserver.be — Emulator-Ersatz für das Tasmota-Modul `webserver`
# Signaturen wie xdrv_52_3_berry_webserver.ino (Tasmota 15.x)

var webserver = module("webserver")

webserver.HTTP_ANY = 0
webserver.HTTP_GET = 1
webserver.HTTP_OPTIONS = 2
webserver.HTTP_POST = 3
webserver.HTTP_OFF = 0
webserver.HTTP_USER = 1
webserver.HTTP_ADMIN = 2
webserver.HTTP_MANAGER = 3
webserver.HTTP_MANAGER_RESET_ONLY = 4
webserver.BUTTON_MAIN = 0
webserver.BUTTON_CONFIGURATION = 1
webserver.BUTTON_INFORMATION = 2
webserver.BUTTON_MANAGEMENT = 3
webserver.BUTTON_MODULE = 4

webserver.on = def (prefix, f, method)
  if type(prefix) != 'string' || type(f) != 'function'
    raise "type_error", "webserver.on(prefix:string, closure [, method:int])"
  end
  if method == nil method = 0 end
  for r: _emu.routes
    if r[0] == prefix && r[2] == method r[1] = f return end
  end
  _emu.routes.push([prefix, f, method])
end

webserver.remove_route = def (prefix, method)
  var i = 0
  while i < size(_emu.routes)
    if _emu.routes[i][0] == prefix && (method == nil || _emu.routes[i][2] == method)
      _emu.routes.remove(i)
      return true
    end
    i += 1
  end
  return false
end

webserver.state = def () return 2 end
webserver.check_privileged_access = def () return true end

webserver.content_send = def (s) _emu.web_out.push(str(s)) end
webserver.content_flush = def () end
webserver.content_send_style = def (s)
  _emu.web_out.push("<style>body{font-family:verdana,sans-serif}</style>")
  if s != nil _emu.web_out.push(str(s)) end
end
webserver.content_start = def (title)
  _emu.web_code = 200
  _emu.web_mime = "text/html"
  _emu.web_out.push("<!DOCTYPE html><html><head><meta charset='utf-8'><title>" + str(title) + "</title></head><body>")
end
webserver.content_stop = def () _emu.web_out.push("</body></html>") end
webserver.content_open = def (code, mime)
  _emu.web_code = code
  _emu.web_mime = mime
end
webserver.content_close = def () end
webserver.content_response = def (s)
  _emu.web_code = 200
  _emu.web_mime = "text/plain"
  _emu.web_out.push(str(s))
end
webserver.content_button = def (b)
  _emu.web_out.push("<p><form action='/' method='get'><button>Hauptmenü</button></form></p>")
end
webserver.content_status_sticker = def (s) end
webserver.redirect = def (uri)
  _emu.web_code = 302
  _emu.web_mime = "text/plain"
  _emu.web_out.push("Location: " + str(uri))
end
webserver.html_escape = def (s)
  import string
  s = string.replace(str(s), "&", "&amp;")
  s = string.replace(s, "<", "&lt;")
  s = string.replace(s, ">", "&gt;")
  s = string.replace(s, "'", "&#39;")
  return string.replace(s, '"', "&quot;")
end

webserver.arg_size = def () return size(_emu.req_args) end
webserver.has_arg = def (name) return _emu.req_args.contains(name) end
webserver.arg = def (k)
  if type(k) == 'int'
    var i = 0
    for n: _emu.req_args.keys()
      if i == k return _emu.req_args[n] end
      i += 1
    end
    return ""
  end
  var v = _emu.req_args.find(k)
  return v != nil ? v : ""
end
webserver.arg_name = def (k)
  var i = 0
  for n: _emu.req_args.keys()
    if i == k return n end
    i += 1
  end
  return ""
end
webserver.header = def (name) return nil end

return webserver
