# MQTT contracts

Broker default: `127.0.0.1:1883` (local Mosquitto).

All robot topics use the `robot/` prefix. Payload encoding is **JSON UTF-8** unless noted.

## Navigation / scene

| Topic | Direction | QoS | Description |
|-------|-----------|-----|-------------|
| `robot/nav/capture` | brain / mcp / debug → eyes | 1 | Request one perception capture |
| `robot/nav/scene` | eyes → brain + mcp | 0–1 | Traversability summary + hint |

### `robot/nav/capture` payload

```json
{
  "req_id": "a1b2c3…",
  "view": "traverse",
  "timeout_s": 60
}
```

| Field | Meaning |
|-------|---------|
| `req_id` | Correlates the resulting `robot/nav/scene` |
| `view` | `traverse` (default, publishes scene) or `boxes` |
| `timeout_s` | Hint for eyes; requesters also enforce their own wait |

Eyes runs one YOLO + depth (+ Fast-SCNN for `traverse`) pass and publishes `robot/nav/scene`. Debug web **Capture** uses the same streamer path without requiring MQTT.

### `robot/nav/scene` payload

```json
{
  "ts": 1710000000.0,
  "req_id": "a1b2c3…",
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
| `req_id` | Present when this scene answers a capture request |
| `closest_m` | Nearest obstacle in the free/near band (meters) |
| `sectors` | Rough free range left / center / right (meters) |
| `floor_ahead_pct` | Fraction of lower image labeled walkable floor |
| `objects` | YOLO hits with metric distance when depth agrees |
| `costmap` | Compact BEV for planners (`rle` pairs `[value, run]`) |
| `hint` | One-line English for LLM / UI |

**brain** requests a capture only when the user utterance is about seeing the room (or when `mqtt.capture_before_reply: true`). It injects compact `CameraJSON` into the system prompt; object names stay English and must be translated when spoken.

**mcp** tool `capture_scene` publishes the same capture request and returns the matching scene; `get_scene` only reads the cache.

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
| `robot/nav/capture` | brain, mcp, tests | eyes |
| `robot/nav/scene` | eyes | brain, mcp, future planner |
| `robot/drive/cmd` | eyes pad, drive pad, mcp (gated), **brain face-speaker** | drive bridge |
| `robot/drive/stop` | any UI / mcp | drive bridge |
| `robot/drive/status` | drive bridge | eyes UI, mcp |

## Safety notes

- Prefer short `dur>0` nudges from agents; leave `ROBOT_MCP_ALLOW_MOTION` unset/`0` unless intentionally enabling.
- `drive_stop` / `robot/drive/stop` is always allowed from mcp.
- Scene hints are advisory; Cityscapes floor labels can under-detect apartment floors.
- Capture is on-demand (not continuous inference) so GPU stays idle between requests.
