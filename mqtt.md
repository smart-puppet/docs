# MQTT contracts

Broker default: `127.0.0.1:1883` (local Mosquitto).

All robot topics use the `robot/` prefix. Payload encoding is **JSON UTF-8** unless noted.

## Navigation / scene (`eyes` → bus)

| Topic | Direction | QoS | Description |
|-------|-----------|-----|-------------|
| `robot/nav/scene` | eyes publish; brain + mcp subscribe | 0–1 | Traversability summary + hint |

### `robot/nav/scene` payload

```json
{
  "ts": 1710000000.0,
  "closest_m": 1.5,
  "sectors": { "left": 2.2, "center": 2.0, "right": 1.5 },
  "floor_ahead_pct": 0.42,
  "objects": [
    { "label": "chair", "conf": 0.8, "dist_m": 1.5, "bearing": "center" }
  ],
  "costmap": {
    "res_m": 0.05,
    "w": 60,
    "h": 80,
    "encoding": "rle",
    "data": [[255, 10], [100, 5]]
  },
  "hint": "path mostly clear; closest 1.5m"
}
```

| Field | Meaning |
|-------|---------|
| `closest_m` | Nearest obstacle in the free/near band (meters) |
| `sectors` | Rough free range left / center / right (meters) |
| `floor_ahead_pct` | Fraction of lower image labeled walkable floor |
| `objects` | YOLO hits with metric distance when depth agrees |
| `costmap` | Compact BEV for planners (`rle` pairs `[value, run]`) |
| `hint` | One-line English for LLM / UI |

**brain** turns this into: `Vision: <hint> | Objects: …` on the system prompt.

## Drive (`clients` ↔ `drive`)

Prefix default: `robot/drive` (override with env / config).

| Topic | Direction | Description |
|-------|-----------|-------------|
| `robot/drive/cmd` | client → bridge | Motion / clear / heartbeat |
| `robot/drive/stop` | client → bridge | Immediate estop |
| `robot/drive/status` | bridge → bus | MCU / bridge status JSON |
| `robot/drive/debug` | bridge → bus | Optional verbose debug |

### `robot/drive/cmd` (common fields)

```json
{ "cmd": "forward", "speed": 120, "ttl": 300, "dur": 0 }
```

| `cmd` | Notes |
|-------|--------|
| `forward` / `backward` | Hold needs `ttl` heartbeats if `dur=0` |
| `turn_left` / `turn_right` | Optional `counts` for encoder turns |
| `idle` | Stop current without estop latch |
| `clear` | Clear estop after `stop` |
| `heartbeat` / `status` | Watchdog / query |

See [drive README](https://github.com/smart-puppet/drive) for UART mapping and FUSA behavior.

## Who publishes / consumes

| Topic | Publishers | Consumers |
|-------|------------|-----------|
| `robot/nav/scene` | eyes | brain, mcp, future planner |
| `robot/drive/cmd` | eyes pad, drive pad, mcp (gated), future planner | drive bridge |
| `robot/drive/stop` | any UI / mcp | drive bridge |
| `robot/drive/status` | drive bridge | eyes UI, mcp |

## Safety notes

- Prefer short `dur>0` nudges from agents; leave `ROBOT_MCP_ALLOW_MOTION` unset/`0` unless intentionally enabling.
- `drive_stop` / `robot/drive/stop` is always allowed from mcp.
- Scene hints are advisory; Cityscapes floor labels can under-detect apartment floors.
