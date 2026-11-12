# path.be — Emulator-Ersatz für das Tasmota-Modul `path` (LittleFS)
# Pfade wie auf dem Gerät ("/datei.csv"), abgebildet auf das Emulator-Dateisystem.

var path = module("path")

path.exists = def (n)
  import os
  return os.path.exists(_emu.fs_path(n))
end

path.isdir = def (n)
  import os
  return os.path.isdir(_emu.fs_path(n))
end

path.listdir = def (n)
  import os
  var p = _emu.fs_path(n == nil ? "/" : n)
  if !os.path.isdir(p) return [] end
  var out = []
  for f: os.listdir(p)
    if f != "." && f != ".." out.push(f) end
  end
  return out
end

path.remove = def (n)
  import os
  var p = _emu.fs_path(n)
  if !os.path.exists(p) return false end
  return os.remove(p) == true || !os.path.exists(p)
end

path.mkdir = def (n)
  import os
  return os.mkdir(_emu.fs_path(n)) == true
end

path.rmdir = def (n)
  import os
  return os.remove(_emu.fs_path(n)) == true
end

path.rename = def (a, b)
  import os
  var f = open(a, "r")
  var s = f.read()
  f.close()
  var g = open(b, "w")
  g.write(s)
  g.close()
  os.remove(_emu.fs_path(a))
  return true
end

path.last_modified = def (n)
  import os
  return os.path.exists(_emu.fs_path(n)) ? _emu.utc : nil
end

path.format = def (b) raise "not_implemented_error", "path.format ist im Emulator gesperrt" end

return path
