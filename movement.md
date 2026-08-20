# Movement and play

Puppet rolls using **eyes** (who is where, what is blocked) and **drive** (short timed nudges). Brain owns the play loop so voice can start and stop games without putting a planner inside the camera process.

This is **step 1** of a longer roadmap. Later steps are listed at the end so we do not pretend hide-the-robot or map-based nav already exist.

## Bring-up

Same order as [architecture.md](architecture.md), plus play enabled in brain. On the robot, use [systemd.md](systemd.md) (`puppet.target`; drive bridge starts first).

1. Mosquitto
2. **drive** host bridge (MCU on UART)
3. **eyes** Eye UI (must be in `traverse` / listening for `robot/nav/capture`)
4. **brain** with `play.enabled: true` and `play.allow_motion: true`

Clear estop if the pad or a previous stop latched it (`robot/drive/cmd` `{"cmd":"clear"}`).

## How a tick works

```text
kid: "follow me"
   → LLM speaks a short yes and emits hidden <<follow>> (not spoken)
   → PlaySupervisor mode = follow

loop (paused while Kace thinks or talks):
   1. publish robot/nav/capture
   2. wait for robot/nav/scene (YOLO person + sectors + closest_m)
   3. policy picks idle | forward | turn_left | turn_right
   4. publish robot/drive/cmd with dur>0 (never hold/heartbeat)
```

Facing the child from ReSpeaker DoA is **not** an LLM tag: each utterance still turns the chassis toward the latched voice direction before Gemma runs.

Hidden tags (stripped before Piper):

| Tag | Effect |
|-----|--------|
| `<<follow>>` | start follow |
| `<<seek>>` | start hide-and-seek |
| `<<stop>>` | idle / stay still |
| `<<back>>` | stop follow/seek, then one short reverse nudge (`dur>0`) |
| `<<look>>` | request a fresh `robot/nav/capture`; speak a glimpse if the reply did not name objects |

`ACTION: follow` on its own last line is accepted as well. MQTT `robot/play/cmd` still sets the same modes without the LLM.

Eyes still infers **on demand**. Follow rate is “as fast as one capture” (often 1–3 s on Jetson), not 30 FPS. That is intentional: GPU stays free for STT/LLM between ticks.

## Behaviors (step 1)

| Mode | Voice | Motion |
|------|-------|--------|
| **follow** | Kid asks to come / follow; Gemma adds `<<follow>>`. Saying stop / halt / arrête while following idles immediately (does not wait for `<<stop>>`). | Turn toward YOLO `person` bearing; roll forward if centered and far; stop at `stop_m`. If nobody is in view at start, spin in place for one full turn then say there is no one to follow. If a tracked person leaves the left or right of the frame, keep turning that way until they are back or 180°, then the same full-turn look, then give up. |
| **seek** | Kid asks for hide-and-seek; Gemma adds `<<seek>>` | Turn in place until a person appears, then follow until `found_m`, then idle and say “found you”. Never roll toward last voice while lost. After `seek_giveup_ticks` with no person, idle and say it gave up. |
| **idle** | Kid asks to stop; wheels idle at once if already in follow/seek. Gemma should still add `<<stop>>`. | Soft stop (`idle`), no estop latch |
| **back** | Kid asks to reverse; Gemma adds `<<back>>` | One `backward` nudge, then idle |

MQTT (same modes, no voice):

```json
{ "mode": "follow" }
{ "mode": "seek" }
{ "mode": "idle" }
{ "mode": "back" }
```

on `robot/play/cmd`. Status (last nudge, person distance) is published on `robot/play/status`.

## Obstacle avoidance (step 1)

Policy is **reactive**, not a costmap A* planner:

- If `closest_m` (or center sector) is closer than the tracked person by `person_margin_m`, treat it as furniture and **turn toward the freer side** instead of driving forward.
- If the nearest hit *is* the person, do not treat them as an obstacle — stop at `follow.stop_m` (~0.9 m).
- People are `NO_GO` in the eyes free-mask, so `closest_m` often *is* the child. The margin check is what keeps follow from freezing 2 m away.

Voice **can** reverse on request (`<<back>>`, one 500 ms nudge). Follow still does **not** auto-reverse around furniture (see step 4).

## Safety

| Rule | Why |
|------|-----|
| `dur>0` only | MCU ends the segment; no heartbeat hold from the agent |
| Pause while THINKING/SPEAKING | YOLO and Gemma should not fight for GPU; wheels do not roll over speech |
| `play.allow_motion: false` | Voice still answers; wheels stay still |
| `robot/drive/stop` | Hardware estop; play will idle on the next tick |
| Conservative default speeds | `forward_speed: 90`, 500 ms nudges — tune on carpet |

An adult should stay in the room. This is a kid robot, not a warehouse AGV.

## Config (`brain/config/default.yaml` → `play`)

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `true` | Start the supervisor thread |
| `allow_motion` | `true` | Actually publish drive nudges |
| `tick_s` | `0.15` | Wait between ticks (capture dominates) |
| `follow.stop_m` | `0.9` | Personal-space stop |
| `follow.obstacle_m` | `0.5` | Hard stop / sidestep |
| `follow.forward_dur_ms` | `500` | Length of one roll |
| `follow.backward_dur_ms` | `500` | Length of one reverse nudge |
| `follow.turn_dur_ms` | `280` | Length of a bearing correction |
| `follow.found_m` | `1.15` | Seek → “found” idle |
| `follow.seek_giveup_ticks` | `24` | Seek → idle if no person for this many captures |

Disable without code changes: `play.allow_motion: false` or `play.enabled: false`.

## What we did **not** build yet

### Step 2 — richer seek / found speech

- Count-out loud before seeking (today seek starts with Gemma’s reply only)
- Ignore the adult operator vs the hiding child (multi-person)
- LLM-generated “found you” instead of the canned Piper line

### Step 3 — robot hides

- Need a “go to a corner” behavior using sectors/costmap, then wait
- Need a timeout and “come find me” voice line
- Harder: no localization, so hide is “turn away + roll to a free sector”, not a mapped room

### Step 4 — local planner

- Decode BEV costmap RLE → grid
- Short-horizon DWA / A* to a person goal
- Reverse and recovery spins
- Documented earlier as “out of scope”; this file is the new home for that work

## Files

| Path | Role |
|------|------|
| `brain/src/puppet/play/policy.py` | Pure scene → nudge (unit tested) |
| `brain/src/puppet/play/actions.py` | Parse hidden `<<follow>>` / `<<back>>` / `<<look>>` tags from Gemma |
| `brain/src/puppet/play/supervisor.py` | Capture loop + MQTT cmd/status |
| `brain/src/puppet/mqtt/drive.py` | `nudge` / `idle` / `estop` |
