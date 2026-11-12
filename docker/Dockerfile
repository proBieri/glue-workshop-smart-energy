# Dockerfile — Werkzeuge für den gPlug-Workshop
#
# Ziele (docker compose wählt sie über "target"):
#   tools     Berry-Interpreter (aus der Tasmota-Quelle, gleiche Version wie
#             auf dem gPlug) + Python: build.sh, test.sh, Emulator
#   opencode  wie tools, plus der KI-Agent opencode

# --- Berry aus der Tasmota-Quelle bauen -------------------------------------
FROM debian:bookworm-slim AS berry
ARG TASMOTA_REF=v15.3.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates build-essential python3 \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${TASMOTA_REF}" --filter=blob:none --sparse \
        https://github.com/arendst/Tasmota.git /src \
 && cd /src \
 && git sparse-checkout set --no-cone \
        /lib/libesp32/berry/ /lib/libesp32/berry_mapping/ \
        /lib/libesp32/berry_int64/ /lib/libesp32/re1.5/ /lib/libesp32/berry_custom/ \
 && cd lib/libesp32/berry \
 # Abweichung vom Gerät: Datei- und Zeileninfo für Laufzeitfehler. Ohne sie
 # meldet der Emulator nur "index_error" ohne Stelle — gemessen 01.11.2026:
 # Kimi brauchte ~60 Schritte (≈8 Mio. Tokens), um so eine Stelle zu raten.
 && sed -i -E 's/^(#define BE_DEBUG_(SOURCE_FILE|RUNTIME_INFO)[[:space:]]+)0/\11/' default/berry_conf.h \
 && make -j"$(nproc)" \
 && install -m 755 berry /usr/local/bin/berry \
 && berry -v

# --- Build, Tests, Emulator --------------------------------------------------
FROM python:3.12-slim-bookworm AS tools
COPY --from=berry /usr/local/bin/berry /usr/local/bin/berry
ENV PYTHONUNBUFFERED=1
WORKDIR /workshop
EXPOSE 8080
CMD ["python3", "emulator/server.py"]

# --- KI-Agenten im Container: opencode und Claude Code ----------------------
# Alles läuft im Container (auch unter Windows): Agent, Berry, build.sh, test.sh.
FROM tools AS agent
ARG OPENCODE_VERSION=
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git ripgrep less procps \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://opencode.ai/v2/install -o /tmp/install.sh \
 && bash /tmp/install.sh ${OPENCODE_VERSION:+--version "$OPENCODE_VERSION"} \
 && rm /tmp/install.sh
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/claude.sh \
 && bash /tmp/claude.sh \
 && rm /tmp/claude.sh
ENV PATH="/root/.opencode/bin:/root/.local/bin:${PATH}"
RUN git config --global --add safe.directory /workshop \
 && opencode --version && claude --version
COPY docker/opencode-start.sh /usr/local/bin/opencode-start
# Windows: ohne .gitattributes (z.B. von Hand kopiert) käme das Skript mit CRLF und
# ohne Ausführungsrecht an — dann startet der Container nicht ("bash\r: No such file").
RUN sed -i 's/\r$//' /usr/local/bin/opencode-start && chmod 755 /usr/local/bin/opencode-start
# Emulator-Werkzeuge fest im Image: im Agent-Container ist /workshop/emulator
# ausgeblendet (Agenten lasen sonst die Interna und bezahlten sie bei jedem
# Schritt). build.sh/test.sh nutzen EMU_DIR. Nach Änderungen am Emulator:
# docker compose build
COPY emulator /opt/gplug/emulator
ENV EMU_DIR=/opt/gplug/emulator
ENTRYPOINT ["opencode-start"]
