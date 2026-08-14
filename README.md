# Puppet docs

Shared documentation for the [smart-puppet](https://github.com/smart-puppet) stack (Jetson Orin). Per-module details live in each repo; this repo covers how the pieces fit together.

| Doc | Contents |
|-----|----------|
| [architecture.md](architecture.md) | Modules, roles, data flow |
| [mqtt.md](mqtt.md) | Topic contracts (`robot/*`) |
| [movement.md](movement.md) | Follow, obstacles, hide-and-seek (step-by-step) |

## Modules at a glance

| Repo | Role |
|------|------|
| [eyes](https://github.com/smart-puppet/eyes) | Perception — on-demand capture → scene |
| [drive](https://github.com/smart-puppet/drive) | Locomotion — MQTT ↔ UART ↔ MCU |
| [brain](https://github.com/smart-puppet/brain) | Conversation — STT / LLM / TTS; requests captures |

Realtime traffic uses **Mosquitto**. Modules do not call each other over HTTP in production.
