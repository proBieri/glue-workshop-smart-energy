# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This project was set up with **opencode**, which reads `AGENTS.md` (not this file). All shared project guidance lives there — edit `AGENTS.md`, not this file.

@AGENTS.md

## Claude Code specifics

- Commands (`/plan`, `/build`) and skills in `.claude/` mirror `.opencode/`. A PostToolUse hook (`.claude/settings.json`) runs `agents-sync.sh` after every edit, so editing either side is enough; to delete a command/skill, delete it on both sides. Claude Code ignores the `agent:` field of a command — run `/plan` in plan mode (`Shift+Tab`).
- For WebUI, chart, heap, HTTP-fetch or latency work, load the project skill `tasmota-lowmem-webui` (`.claude/skills/tasmota-lowmem-webui/SKILL.md`, kept in sync with `.opencode/skills/` by `agents-sync.sh`); the Berry/Tasmota section of `AGENTS.md` is a condensed version of it.
