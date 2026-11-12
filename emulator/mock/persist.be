# persist.be — Emulator-Ersatz für das Tasmota-Modul `persist`
# Gleiches Verhalten wie berry_tasmota/src/embedded/persist.be:
# Werte landen als JSON in "_persist.json" im (virtuellen) Dateisystem.

var persist_module = module("persist")

persist_module.init = def (m)

  class Persist
    var _p
    var _dirty

    def init()
      self._p = {}
      self._dirty = false
      self.load()
    end

    def member(key)
      if key == "_p" || key == "_dirty" return nil end
      return self._p.find(key)
    end

    def setmember(key, value)
      self._p[key] = value
      self._dirty = true
    end

    def remove(k)
      self._p.remove(k)
      self._dirty = true
    end

    def has(k) return self._p.contains(k) end
    def find(k, d)
      var v = self._p.find(k)
      return v != nil ? v : d
    end
    def zero() self._p = {} self._dirty = true end
    def dirty() self._dirty = true end

    def load()
      import json
      var f
      try
        f = open("_persist.json", "r")
        var v = json.load(f.read())
        f.close()
        if isinstance(v, map) self._p = v end
      except .. as e
        if f != nil f.close() end
      end
      self._dirty = false
    end

    def save(force)
      if self._dirty || force == true
        import json
        var f = open("_persist.json", "w")
        f.write(json.dump(self._p))
        f.close()
        self._dirty = false
      end
    end
  end

  return Persist()
end

return persist_module
