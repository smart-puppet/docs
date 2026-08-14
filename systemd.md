# systemd

Start Mosquitto, the drive MQTT–UART bridge, eyes, and brain on boot. **Drive (`mqtt_bridge`) starts first** among the Puppet units so wheels and status exist before eyes/brain publish commands.

## Units

| Unit | Process | After |
|------|---------|--------|
| `mosquitto.service` | MQTT broker (distro package) | network |
| `puppet-drive.service` | `drive/host/mqtt_bridge.py` | `mosquitto` |
| `puppet-eyes.service` | eyes debug web + `robot/nav/capture` | `mosquitto`, **`puppet-drive`** |
| `puppet-brain.service` | `puppet` voice | `mosquitto`, **`puppet-drive`**, `puppet-eyes` |
| `puppet.target` | pulls the three Puppet units in | `mosquitto`, `puppet-drive` |

Unit files (edit `User=` and paths if the checkout is not `/home/cvincent/Projects/01-Puppet`):

| File | Repo |
|------|------|
| `deploy/systemd/puppet-drive.service` | [drive](https://github.com/smart-puppet/drive) |
| `deploy/systemd/puppet-eyes.service` | [eyes](https://github.com/smart-puppet/eyes) |
| `deploy/systemd/puppet-brain.service` | [brain](https://github.com/smart-puppet/brain) |
| `deploy/systemd/puppet.target` | this repo |

The drive debug pad is **not** a service. Use the pad on the eyes UI (`http://127.0.0.1:8091`).

## Install

On the Jetson, from the workspace that contains `drive/`, `eyes/`, `brain/`, and `docs/`:

```bash
ROOT=/home/cvincent/Projects/01-Puppet

sudo apt-get install -y mosquitto mosquitto-clients

sudo cp "$ROOT/drive/deploy/systemd/puppet-drive.service" /etc/systemd/system/
sudo cp "$ROOT/eyes/deploy/systemd/puppet-eyes.service" /etc/systemd/system/
sudo cp "$ROOT/brain/deploy/systemd/puppet-brain.service" /etc/systemd/system/
sudo cp "$ROOT/docs/deploy/systemd/puppet.target" /etc/systemd/system/

# Serial (MCU) and audio/video groups — skip any group that does not exist
sudo usermod -aG dialout,plugdev,audio,video,render cvincent

# Keep the user session (PulseAudio) after logout so brain can use the ReSpeaker at boot
sudo loginctl enable-linger cvincent

sudo systemctl daemon-reload
sudo systemctl enable --now mosquitto
sudo systemctl enable --now puppet.target
```

Log out and back in (or reboot) once after `usermod` so the supplementary groups apply to the service user.

If you previously installed the old `puppet.service` name:

```bash
sudo systemctl disable --now puppet.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/puppet.service
sudo systemctl daemon-reload
```

## Enable, start, stop

```bash
sudo systemctl enable --now puppet.target   # boot + start the stack
sudo systemctl start puppet.target          # start now
sudo systemctl stop puppet.target           # stop brain, eyes, drive
sudo systemctl disable puppet.target        # do not start on boot
```

Start order when the target comes up: Mosquitto → **drive bridge** → eyes and brain (`After=` / `Before=` on the units).

One piece only (drive still comes up first if you start eyes or brain):

```bash
sudo systemctl start puppet-drive
sudo systemctl start puppet-eyes
sudo systemctl start puppet-brain
```

Restart one process after a config or code change:

```bash
sudo systemctl restart puppet-brain
sudo systemctl restart puppet-eyes
sudo systemctl restart puppet-drive
```

Language changes from the eyes UI (`language.active`) apply on the **next brain start** — `sudo systemctl restart puppet-brain`.

## Logs

systemd sends stdout/stderr to the journal. Follow everything:

```bash
journalctl -u mosquitto -u puppet-drive -u puppet-eyes -u puppet-brain -f
```

One unit, this boot:

```bash
journalctl -u puppet-drive -b --no-pager
journalctl -u puppet-eyes -b --no-pager
journalctl -u puppet-brain -b --no-pager
```

Errors only:

```bash
journalctl -u puppet-drive -u puppet-eyes -u puppet-brain -p err -b
```

Health:

```bash
systemctl status puppet.target puppet-drive puppet-eyes puppet-brain mosquitto --no-pager
```

Eyes also mirrors `robot/log/brain` and `robot/log/drive` in the debug web log panes (`http://127.0.0.1:8091`). Use the journal when the UI is down or a unit never reaches MQTT.

## If something is wrong

| Symptom | Check |
|---------|--------|
| `puppet.target` inactive | `systemctl status puppet.target`; `journalctl -u puppet-drive -b` (drive is the first Puppet unit) |
| Drive: `No such file or directory: '/dev/ttyACM0'` | MCU USB unplugged or enumerating as `ttyACM1`. Unplug/replug; `ls /dev/ttyACM*`; set `ROBOT_SERIAL` / `--serial` in the unit |
| Drive: `Permission denied` on the serial port | User not in `dialout`; reboot after `usermod` |
| `mosquitto.service` failed / connection refused | `sudo systemctl start mosquitto`; `ss -lntp \| grep 1883` |
| Eyes: `missing engine` | Build TensorRT engines; see eyes README |
| Eyes: camera busy / no `/dev/video*` | Another process holds the camera; `fuser /dev/video0` |
| Brain: `No .venv` / `puppet` not importable | Create the venv and `pip install -e .` in `brain/` |
| Brain: `PulseAudio: Unable to connect: Connection refused` / silent TTS / no mic | System unit cannot see the user Pulse socket. `sudo loginctl enable-linger cvincent`, confirm `ls /run/user/1000/pulse/native`, then `sudo systemctl restart puppet-brain`. Journal should show `Mic opened` with a ReSpeaker name, not only `'default'` after pulse refused |
| Brain: `PulseAudio socket missing` (ExecStartPre failed) | User session not running. Enable linger (above) or log in once so `user@1000.service` starts Pulse |
| Wheels never move | Drive must be **active** (`systemctl is-active puppet-drive`); clear estop: `mosquitto_pub -t robot/drive/cmd -m '{"cmd":"clear"}'` |
| Unit restart loop | `journalctl -u <unit> -b -e`; fix the crash, then `sudo systemctl reset-failed` |

Do not run `scripts/run_puppet.sh`, `scripts/run_debug_web.sh`, or `mqtt_bridge.py` by hand while the matching unit is active — they will fight over the mic, camera, or serial port. Stop the unit first: `sudo systemctl stop puppet-brain`.
