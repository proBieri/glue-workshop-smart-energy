# mqtt.be — Emulator-Ersatz für das Tasmota-Modul `mqtt` (nur Logausgabe)

var mqtt = module("mqtt")

mqtt.publish = def (topic, payload, retain)
  print("EMU: MQTT publish " + str(topic) + " " + str(payload))
end
mqtt.subscribe = def (topic, f) print("EMU: MQTT subscribe " + str(topic)) end
mqtt.unsubscribe = def (topic) end
mqtt.connected = def () return true end

return mqtt
