# compile.be — Kompilierprüfung für build.sh
#
#   berry -m emulator/mock emulator/compile.be build/autoexec.be
#
# Übersetzt die zusammengefügte App mit dem Berry-Compiler (ohne sie
# auszuführen). Vorher werden die Tasmota-Globals des Emulators geladen,
# damit `tasmota`, `webclient` & Co. bekannt sind wie auf dem Gerät.
# Fehlerzeilen werden auf die Quelldatei zurückgerechnet (#@@-Markierungen).

import string
import os

var app = _argv[1]
var mock_dir = size(_argv) > 2 ? _argv[2] : "emulator/mock"
compile(mock_dir + "/emu.be", "file")()

var f = open(app, "r")
var src = f.read()
f.close()

def quelle(zeile)
  var datei = app
  var start = 0
  var nr = 1
  for l: string.split(src, "\n")
    if nr > zeile break end
    if string.startswith(l, "#@@ ")
      datei = l[4 ..]
      start = nr
    end
    nr += 1
  end
  return datei + ":" + str(zeile - start)
end

try
  compile(src, "string")
  print(string.format("  Kompiliert: %s (%i Byte Quelltext)", app, size(src)))
except .. as e, m
  m = str(m)
  # Meldung hat die Form "string:123: ..." → Quelldatei:Zeile
  var p = string.find(m, ":")
  var q = p >= 0 ? string.find(m, ":", p + 1) : -1
  if p >= 0 && q > p
    var z = int(m[p + 1 .. q - 1])
    if z > 0 m = quelle(z) + m[q ..] end
  end
  print("FEHLER beim Kompilieren: " + m)
  os.exit(1)
end
