#!/usr/bin/env python3
"""quelle.py — Zeilen in build/autoexec.be auf die Quelldatei zurückrechnen.

build.sh fügt gplug/*.be zu einer autoexec.be zusammen und setzt vor jede Datei
eine Zeile "#@@ gplug/datei.be". Berry meldet Laufzeitfehler aber mit der Zeile
in autoexec.be ("build/autoexec.be:212: in function `uc1_abruf`"). Dieses Modul
macht daraus "gplug/uc1_preise.be:57" — so findet ein Agent die Stelle sofort,
statt sie mit Debug-Ausgaben zu suchen.

Als Filter (test.sh):  berry … | python3 emulator/quelle.py build/autoexec.be
Als Modul (server.py): Quelle(pfad).zeile(text)
"""
import os
import re
import sys

_REF = re.compile(r"(\S*autoexec\.be):(\d+)")
# Traceback-Zeilen aus dem Emulator selbst: für die App-Fehlersuche nur Rauschen
_INTERN = re.compile(r"^\s+(<native>|\S*emulator/\S+:\d+):")


class Quelle:
    def __init__(self, app):
        self.app = app
        self.mtime = None
        self.marken = []          # [(zeile_der_markierung, datei)]

    def _laden(self):
        try:
            m = os.path.getmtime(self.app)
        except OSError:
            self.marken = []
            return
        if m == self.mtime:
            return
        self.mtime = m
        self.marken = []
        with open(self.app, encoding="utf-8", errors="replace") as f:
            for nr, z in enumerate(f, 1):
                if z.startswith("#@@ "):
                    self.marken.append((nr, z[4:].strip()))

    def ort(self, zeile):
        datei, start = None, 0
        for nr, d in self.marken:
            if nr > zeile:
                break
            datei, start = d, nr
        return f"{datei}:{zeile - start}" if datei else None

    def zeile(self, text):
        """Zeile mit Quellort, oder None für Emulator-interne Traceback-Zeilen."""
        if _INTERN.match(text):
            return None
        if "autoexec.be:" not in text:
            return text
        self._laden()

        def ersetzen(m):
            return self.ort(int(m.group(2))) or m.group(0)
        return _REF.sub(ersetzen, text)


if __name__ == "__main__":
    q = Quelle(sys.argv[1] if len(sys.argv) > 1 else "build/autoexec.be")
    for z in sys.stdin:
        z = q.zeile(z)
        if z is not None:
            sys.stdout.write(z)
            sys.stdout.flush()
