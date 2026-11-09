# SO101 leader/follower: teleoperation, data collection and inference with a pretrained policy

A hands-on setup for the [LeRobot SO101 guide](https://huggingface.co/docs/lerobot/main/en/so101). You
teleoperate the arm, record demonstrations, and run a **pretrained policy downloaded from the Hugging Face
Hub** on the real arm. Training is out of scope. The work is split across two machines:

| Runs on the **PC** (your computer) | Runs on the **Spark** |
|---|---|
| Camera server (USB cameras → network) | Policy server (the policy's forward pass, on the GPU) |
| Motor setup, calibration | |
| Teleoperation (leader → follower) | |
| Data recording | |
| Robot client (sends observations, executes actions) | |

Everything is pinned to **LeRobot 0.6.1** (PyPI) with **torch 2.11**, Python 3.12.

---

## 1. The architecture, and why it looks like this

```
                         PC  (arms + cameras are plugged in here)
 ┌──────────────────────────────────────────────────────────────────────────┐
 │  USB cam 0 ─┐                                                            │
 │  USB cam 1 ─┴─► camera server ──ZMQ :5555 (front)────┐                   │
 │                (opens cameras ONCE)  :5556 (wrist)───┤                   │
 │                                                      ▼                   │
 │  leader arm ──USB──► lerobot-teleoperate / lerobot-record ──► dataset    │
 │  follower arm ◄─USB─┘            (data collection)           (data/…)    │
 │                                                                 │        │
 │  follower arm ◄─USB── robot client ◄── ZMQ cameras              │ push   │
 └──────────────────────────────┬──────────────────────────────────┼────────┘
            observations ▲      │ gRPC :8090                       ▼
            action chunks ▼     │                        Hugging Face Hub
 ┌──────────────────────────────┴──────────────────────────────────┼────────┐
 │                           DGX Spark                             │ pull   │
 │   policy server (GPU) ◄── loads ── pretrained policy (from the Hub)      │
 └──────────────────────────────────────────────────────────────────────────┘
```

**Why a camera server?** A USB camera can only be opened by one process. With the server, the cameras
are opened once and published over ZeroMQ, so teleop, recording, the robot client and a debug viewer can
all read them at the same time, locally or over the network. LeRobot has a built-in
`ZMQCamera` (`type: zmq`) that reads this stream, so no LeRobot code is patched.

**Why inference on the Spark?** A VLA like SmolVLA (450M parameters) needs a GPU to produce actions fast
enough. With **async inference** the PC keeps controlling the arm at 30 Hz from a queue of actions while
the Spark computes the next *chunk* (50 actions) in parallel. The network delay is hidden by the queue.

**Why a pretrained policy?** You start from a policy that someone has already trained on an SO101 and
published on the Hub (§9). The default is an ACT pick-and-place policy
([`BoyuZhao/so101-act-pick-and-place`](https://huggingface.co/BoyuZhao/so101-act-pick-and-place)). A small
ACT policy can also run on the Mac itself, with no Spark (§10).

**The Spark is shared.** Several people use it, so the project runs under a dedicated `academy` user
(§9.1), and the policy server listens on port **8090** (8080, LeRobot's default, is a popular port that other services on a shared
machine often already use).
Students never log in to the Spark: they only run the robot client on their own PC.

### macOS and Docker: read this first

**Docker Desktop on macOS cannot pass USB serial ports or cameras into a container.** Docker runs inside
a Linux VM that has no access to your Mac's USB devices. The arms (serial ports) and cameras therefore
cannot work from a container on a Mac. So:

| Your PC is… | PC side runs | Spark side runs |
|---|---|---|
| **macOS** | **natively** in a `uv` venv (`scripts/setup_native.sh`), same scripts | Docker |
| **Linux** | Docker (`compose.pc.yml`), or natively | Docker |

Both paths use the same `requirements/pc.txt`, the same `.env` and the same `scripts/`, so what you learn
carries over 1:1. The PC Docker image builds fine on a Mac (useful for testing), but it only *sees*
hardware on a Linux host.

---

## 2. Project layout

```
.env.example            ← all configuration (ports, IDs, cameras, task, Spark IP). Copy to .env
requirements/pc.txt     ← PC packages:    lerobot[feetech,core_scripts,async,pyzmq-dep]
requirements/spark.txt  ← Spark packages: lerobot[training,smolvla,async] (policy server)
docker/pc.Dockerfile    ← PC image (Linux hosts)
docker/spark.Dockerfile ← Spark image (aarch64 + CUDA 13)
docker/udev/            ← Linux: stable /dev/so101_follower, /dev/so101_leader names
compose.pc.yml          ← camera-server + robot services (Linux PC)
compose.spark.yml       ← policy-server service (Spark); the train service is unused
camera_server/serve.py  ← the camera server
camera_server/snapshot.py ← "what does LeRobot see?" check
scripts/                ← one script per step, numbered in order. Each prints the real
                          lerobot command before running it, so you learn the CLI.
scripts/robot_client.py ← launcher for LeRobot's async robot client, with two fixes (§10)
data/                   ← (created) calibration files + datasets + HF cache. Back it up!
logs/                   ← (created) LeRobot debug logs, in the folder you ran the script from; not committed
```

Where things are stored (set by `HF_LEROBOT_HOME` in `.env`):
- calibration: `data/huggingface/lerobot/calibration/robots/so_follower/<FOLLOWER_ID>.json` and
  `.../teleoperators/so_leader/<LEADER_ID>.json`
- dataset: `data/huggingface/lerobot/<HF_USER>/<DATASET_NAME>/`

---

## 3. Before you start

1. **Assemble both arms** following the [SO101 guide](https://huggingface.co/docs/lerobot/main/en/so101).
   The leader uses motors with mixed gear ratios (1/191, 1/345, 1/147); the follower uses six 1/345.
   Don't mix them up.
2. **Hugging Face account and token** with *write* access: https://huggingface.co/settings/tokens.
   Recorded datasets are uploaded to the Hub, and the Spark downloads the pretrained policy from it.
   `HF_USER` must be your exact Hub username (see your profile URL).
3. **Network**: PC and Spark on the same LAN. Find the Spark's IP with `hostname -I` on the Spark and put
   it in `SPARK_HOST` (`.env.example` already holds the Academy's). Below, `<SPARK_HOST>` means that IP.
4. **Cameras**: two USB cameras. **CAM1** is a fixed front/top view; **CAM2** is on the wrist.
5. Create your config:
   ```bash
   cp .env.example .env     # then edit: HF_USER, HF_TOKEN, FOLLOWER_PORT, LEADER_PORT …
   ```
   `.env` holds your own token and is never committed. Everything else in `.env.example` (Spark address,
   port, policy, camera names) is already set for the Academy.

> **Camera names matter.** Each camera's name (`CAM1_NAME`, `CAM2_NAME` in `.env`) becomes a policy input
> called `observation.images.<name>`. The names must match what the pretrained policy expects, or it
> refuses to run. The defaults, `front`/`wrist`, match the default ACT policy; SmolVLA-based policies
> usually expect `camera1`/`camera2`. Pick your policy (§9) and set the names **before** you record, so
> your datasets use the same names as inference. A dataset recorded with other names can't be mixed in.

---

## 4. PC setup

### macOS (native)
```bash
brew install uv ffmpeg@8
scripts/setup_native.sh        # creates .venv with Python 3.12 + requirements/pc.txt
scripts/00_check.sh            # prints config, lerobot/torch versions, "Apple MPS available"
```
Scripts activate `.venv` themselves. To use the LeRobot CLI by hand: `source .venv/bin/activate`.
macOS may ask for **camera** permission for your terminal, and for **Accessibility/Input Monitoring**
(keyboard shortcuts while recording). Grant both in System Settings → Privacy & Security.

### Linux (Docker)
Install Docker Engine with the Compose plugin, and let your user run it: `sudo usermod -aG docker $USER`,
then log out and in again.

**Do the hardware steps on the host first.** The `robot` container is started with the arm ports from
`.env` passed in, and Docker refuses to start it while those devices don't exist (the defaults in
`.env.example` are macOS placeholders). For the same reason `01_find_port.sh` and `04_find_cameras.sh`
can't discover anything from inside a container.

1. **Arm ports.** Plug in both arms (powered), then on the host:
   ```bash
   ls -l /dev/serial/by-id/       # one entry per arm, e.g. usb-1a86_USB_Single_Serial_5A7C121717-if00 -> ../../ttyACM0
   ```
   Unplug one arm and list again to see which is which. Then either make the names stable (recommended,
   otherwise `ttyACM0`/`ttyACM1` can swap on reboot): follow `docker/udev/99-so101.rules` and set
   `FOLLOWER_PORT=/dev/so101_follower`, `LEADER_PORT=/dev/so101_leader`; or set `FOLLOWER_PORT`/`LEADER_PORT`
   to the `/dev/ttyACM*` names you saw.
2. **Cameras.** On the host:
   ```bash
   sudo apt install v4l-utils     # if missing
   v4l2-ctl --list-devices        # each camera lists its /dev/video* nodes
   ```
   Many USB cameras create **two** nodes (e.g. `/dev/video0` and `/dev/video1`); the first one of each
   camera is the image stream. So two cameras are often `0` and `2`, not `0` and `1`. Put the numbers in
   `CAM1_DEVICE` (front/top) and `CAM2_DEVICE` (wrist), then check the views in §6 with
   `05b_camera_snapshot.sh`.
3. **Build and check:**
   ```bash
   docker compose -f compose.pc.yml build
   docker compose -f compose.pc.yml --profile robot run --rm robot scripts/00_check.sh
   ```

In the steps below, a command like `scripts/03_calibrate.sh follower` becomes, on Linux Docker:
`docker compose -f compose.pc.yml --profile robot run --rm robot scripts/03_calibrate.sh follower`.
Skip `01_find_port.sh` and `04_find_cameras.sh` (done above), and start the camera server with
`docker compose -f compose.pc.yml up -d camera-server` instead of `05_camera_server.sh`.

The containers run as root, so files they create in `data/` (calibration, datasets) and `logs/` are owned
by root on the host. Everything works, but moving or deleting them needs `sudo`
(or `sudo chown -R $USER: data logs`).

**Linux without Docker** works too, with the same `.venv` as on macOS (Ubuntu/Debian commands):
```bash
sudo apt install ffmpeg build-essential linux-libc-dev   # ffmpeg 4–8; a C compiler builds evdev (recording keys)
curl -LsSf https://astral.sh/uv/install.sh | sh          # installs uv, then open a new terminal
sudo usermod -aG dialout $USER                           # serial-port access; log out and in again
scripts/setup_native.sh                                  # creates .venv with Python 3.12 + requirements/pc.txt
scripts/00_check.sh                                      # expect "CPU only" (or CUDA if the PC has an NVIDIA GPU)
```
Then follow the steps exactly as on macOS, including `01_find_port.sh` and `04_find_cameras.sh`. Scripts
activate `.venv` themselves; to use the LeRobot CLI by hand: `source .venv/bin/activate`. PyPI's Linux
torch is a CUDA build (a few GB to download); it runs fine on a PC without a GPU.

---

## 5. Arms: ports → calibration

The arms come with their motor IDs already set, so there's no motor setup to do.

**5.1 Find the ports** (macOS / Linux without Docker; Linux Docker: done in §4). Run once per arm;
it asks you to unplug its USB cable:
```bash
scripts/01_find_port.sh          # → e.g. /dev/tty.usbmodem585A0076841
```
Put the results into `FOLLOWER_PORT` / `LEADER_PORT` in `.env`. The follower is the arm with a gripper. The leader is the arm with the handle.

**5.2 Calibrate.** Move every joint to the middle of its range, press Enter, then sweep each joint through
its full range. Calibration maps raw encoder ticks to the same joint positions on both arms. That shared
mapping is what makes the follower mirror the leader, and what makes your data reusable.
```bash
scripts/03_calibrate.sh follower
scripts/03_calibrate.sh leader
```
The calibration file is named after the **ID** (`FOLLOWER_ID`, `LEADER_ID`). Never change the IDs
afterwards: a new ID means a new, missing calibration.

**The middle position sets every joint's zero, so do it carefully.** The pose you hold when pressing
Enter becomes 0° for each joint. `wrist_roll` is the one to watch: it turns all the way round, so it's
skipped in the "sweep each joint" step and has no end stops to anchor it. Its 0° is *only* the gripper
rotation you held at that moment. If that differs from the rotation used by whoever trained your policy,
every wrist rotation the policy commands is off by that angle (e.g. the gripper turns sideways when
inference starts). Hold the gripper in the same orientation as the policy's training videos, and use the
same orientation on the leader.

**Joint units.** `USE_DEGREES=true` (the LeRobot 0.6.1 default) reads joints in degrees; `false` uses a
−100…100 scale. The scripts pass it explicitly. It must match the units the policy and your datasets were
recorded with; the default ACT policy uses degrees.

---

## 6. Cameras: find → serve → check

Linux Docker: already done in §4, continue at "Start the server".

```bash
scripts/04_find_cameras.sh       # lists OpenCV indices, saves a test image per camera to outputs/captured_images
```
Look at the images and each camera ID in the terminal, then set `CAM1_DEVICE` to the ID of the front/top
camera and `CAM2_DEVICE` to the ID of the wrist camera in `.env`. On a MacBook, the built-in webcam also
gets an ID (often 0 or 1). Make sure you don't pick it by mistake.
Indices can change when you re-plug cameras, so check again if the views look swapped.

Start the server in its **own terminal** and leave it running:
```bash
scripts/05_camera_server.sh      # logs "capture rates: <CAM1_NAME>=30.0fps <CAM2_NAME>=30.0fps" every 5 s
# Linux Docker:  docker compose -f compose.pc.yml up -d camera-server
```
Check what LeRobot will actually receive:
```bash
scripts/05b_camera_snapshot.sh   # writes snapshots/<CAM1_NAME>.jpg and snapshots/<CAM2_NAME>.jpg
```
No cameras yet? Test the whole pipeline with synthetic ones:
`python camera_server/serve.py --camera camera1=test:red:5555 --camera camera2=test:blue:5556`.

Things to know:
- 2 cameras × 640×480 @ 30 fps is the recommended load. On Linux, two cameras on one USB2 hub often
  need `CAMERA_FOURCC=MJPG`.
- If a camera's rate in the server log is below `CAMERA_FPS`, recording will drop frames. Use more light
  (auto-exposure lowers the fps in the dark), a lower resolution, or separate USB ports.
- Debugging without the server: set `CAMERA_MODE=opencv` and scripts open the cameras directly.
- `ZMQCamera … timeout` means nothing is publishing: the camera server isn't running (it must stay up in
  its own terminal during teleop, recording and inference).

---

## 7. Teleoperation

```bash
scripts/06_teleoperate.sh               # with cameras (rerun viewer opens if DISPLAY_DATA=true)
scripts/06_teleoperate.sh --no-cameras  # arms only
```
Move the leader and the follower copies it. **Practise the task here** until your motion is smooth and
repeatable. Recording a shaky operator records shaky data.

With `DISPLAY_DATA=true` in `.env`, the Rerun viewer shows both camera feeds and the joint positions live.

Stop teleoperation (Ctrl+C) before recording: `07_record.sh` runs teleoperation itself, and an arm's
serial port can only be opened by one process.

---

## 8. Data collection

### How it works
`lerobot-record` runs a loop at 30 Hz. Each tick it reads the leader (that's the **action**), reads the
follower joints and both cameras (that's the **observation**), sends the action to the follower, and
saves both. Videos are encoded while recording (`streaming_encoding`), and at the end the dataset is pushed
to `HF_USER/DATASET_NAME` on the Hub.

A session alternates between two phases:
- **Episode** (recorded): one attempt at the task. It ends after `EPISODE_TIME_S` seconds, or earlier when
  you press **→**. Set `EPISODE_TIME_S` a bit longer than your slowest attempt (60 s is a good default) and
  press **→** as soon as the task is done, so episodes don't end with idle arm footage. It can't be 0:
  an empty episode makes recording crash.
- **Reset** (not recorded): `RESET_TIME_S` seconds to put the scene back for the next episode. The leader
  still drives the follower, so use it to return the arm to its start pose. Press **→** to skip the rest.

A long continuous session is therefore **not** one long episode: it gets cut into `EPISODE_TIME_S` pieces
with unrecorded gaps in between.

```bash
scripts/07_record.sh            # records NUM_EPISODES episodes
scripts/07_record.sh --resume   # adds NUM_EPISODES more to the same dataset
```
Keys (the terminal must be focused): 
**→ / n** end the episode early, 
**← / r** re-record the episode,
**Esc / q** stop and save.

Check your data:

```bash
scripts/08_replay.sh 0          # the follower replays episode 0, then exits
scripts/08_replay.sh 1          # episode 1, and so on
```
Replay plays exactly one episode and then exits. It doesn't continue to the next one. Put the arm and
objects roughly where the episode started first, because replay doesn't look at the scene. You can also
browse the dataset at https://huggingface.co/spaces/lerobot/visualize_dataset (enter your repo id).

### A collection protocol that works
- **Start with 50 episodes** of one task. The `TASK` text is stored with every frame. For a VLA it is
  also the language instruction at inference, so keep it identical to the prompt you use there.
- **Vary the start state deliberately.** Spread object positions over a grid (e.g. 5 positions × 10
  episodes). The policy only generalises across the variation it has seen.
- **Keep everything else fixed**: camera mounts, lighting, table, background. A camera that moves 2 cm
  between recording and inference is a different input. 2 different camera positions should be chosen. Examples: (wrist, top) (wrist, front) (wrist, behind) (side, top). Depends on the type of task being performed.
- **Be consistent**: same strategy every time (same grasp, same approach direction). Discard bad takes
  with ←.
- **Look only at the camera views** for a few episodes. If *you* can't do the task from the images
  alone, the policy can't either; move the cameras.

---

## 9. Spark setup and choosing a pretrained policy

**Students skip §9.1–9.2:** the Academy's Spark is already set up and its policy server is running. This
is for whoever administers the Spark.

### 9.1 A dedicated `academy` user (one time, as an admin)
The Spark is shared, so the project lives under its own user. Nobody logs in as `academy`: you switch to
it from your admin account.
```bash
ssh <admin>@<SPARK_HOST>
sudo adduser academy                    # lowercase: Ubuntu rejects capitals. Optional fields: just Enter
sudo usermod -aG docker academy         # lets it run Docker (note: the docker group is root-equivalent)
echo "DenyUsers academy" | sudo tee /etc/ssh/sshd_config.d/deny-academy.conf
sudo systemctl reload ssh               # no SSH logins as academy
sudo passwd -l academy                  # no password logins at all
sudo -iu academy                        # become academy (asks for YOUR password)
```

### 9.2 Get the project onto the Spark and build
As `academy`, either clone the repository (needs read access to it from the Spark), or copy it from your
PC through your admin account (`academy` can't receive SSH):
```bash
# option A, on the Spark as academy
git clone <repository URL> ~/SO101

# option B, from the PC folder, then move it on the Spark
rsync -av --exclude data --exclude .venv --exclude outputs --exclude snapshots --exclude 'logs' \
  ./ <admin>@<SPARK_HOST>:~/SO101/
#   on the Spark, as <admin>:
sudo cp -r ~/SO101 /home/academy/ && sudo chown -R academy:academy /home/academy/SO101 && rm -rf ~/SO101
```
Then, as `academy`:
```bash
cd ~/SO101
cp .env.example .env                    # set HF_USER / HF_TOKEN (a read token is enough here)
docker compose -f compose.spark.yml build                               # ~7 GB image, once
docker compose -f compose.spark.yml --profile tools run --rm shell scripts/00_check.sh
# expect: CUDA: NVIDIA GB10 … and "GPU matmul ok"
```
The `.env` on the Spark only matters for `POLICY_SERVER_PORT` (keep it **8090**) and the HF token: the
policy itself is chosen by each robot client (§10). DGX OS ships with Docker and the NVIDIA Container
Toolkit.

**Always run the Spark commands as `academy`, from `/home/academy/SO101`.** Docker Compose names the
project after the folder (`so101`), so running `docker compose … up` from another user's copy of the
folder would replace academy's policy server with one using *that* copy's files and `.env`.

### 9.3 Choose a pretrained policy
The default in `.env.example` is
[`BoyuZhao/so101-act-pick-and-place`](https://huggingface.co/BoyuZhao/so101-act-pick-and-place): ACT, cameras
`front` + `wrist` at 640×480, 40 demonstrations, joints in degrees (its author doesn't state the unit; its
saved joint statistics go past ±100, which the −100…100 mode can't produce). Its
[code repository](https://github.com/zbylink/SO101-ACT-Pick-and-Place) has a video of the setup it was
trained in: copy its front camera placement and wrist orientation (§5.2).

To pick another one, search the Hub for models trained on an SO101 (SO100 also works, since the arms
share the same joints):
https://huggingface.co/models?other=lerobot. Open a candidate's `config.json` and check:

| In `config.json` | Must match | Set in `.env` |
|---|---|---|
| `"type"` (`smolvla`, `act`, …) | the policy type | `POLICY_TYPE` |
| `input_features` → `observation.images.<name>` | your camera names, and how many cameras | `CAM1_NAME`, `CAM2_NAME` |
| the image `shape` (e.g. `[3, 480, 640]`) | your camera resolution | `CAMERA_WIDTH`, `CAMERA_HEIGHT` |
| `observation.state` / `action` shape `[6]` | the SO101's 6 joints | nothing; anything else is not an SO101 policy |
| files `policy_preprocessor.json` / `policy_postprocessor.json` | present = LeRobot ≥ 0.4 format | nothing; without them it's an old-format model that LeRobot 0.6.1 can't load directly. Skip it |
| joint units (not in `config.json`) | degrees or −100…100 | `USE_DEGREES` (§5.2) |

Then set `POLICY_PATH` to the model's Hub id (e.g. `some-user/smolvla_so101_pick_place`). For a VLA, also
set `TASK` to the instruction it was trained on; it's usually on the model card or in its dataset.

The scripts expect exactly two cameras. If the policy expects one or three cameras, choose another
policy or adapt `cameras_arg` in `scripts/lib.sh`.

**Set expectations.** A policy trained on someone else's arm, cameras, lighting and objects usually works
poorly on yours without fine-tuning. Rebuild its scene as closely as you can: camera positions, objects,
background, lighting. The model card and its training dataset (viewable in the dataset visualizer) show
what it saw. Low success rates are expected. The point is to learn the inference pipeline and see how
sensitive policies are to setup changes.

## 10. Inference: policy server (Spark) + robot client (PC)

**On the Spark** (admin only; already running at the Academy), as `academy` in `~/SO101`, start the
server. It stays up and restarts by itself after a crash or a reboot:
```bash
docker compose -f compose.spark.yml up -d policy-server     # start in the background
docker compose -f compose.spark.yml logs -f policy-server   # watch it; Ctrl+C stops watching, not the server
```
Healthy: the log shows `--port=8090` and then waits quietly for a client. The server loads **no policy**
by itself.

**On the PC** (camera server running), these `.env` values must match the Spark and the policy. They're
the defaults in `.env.example`:
```bash
SPARK_HOST=<the Spark's IP>                    # the Academy's is already in .env.example
POLICY_SERVER_PORT=8090
POLICY_TYPE=act
POLICY_PATH=BoyuZhao/so101-act-pick-and-place   # the Hub id you picked in §9
CAM1_NAME=front
CAM2_NAME=wrist
USE_DEGREES=true
```
then:
```bash
scripts/11_robot_client.sh
```
The client connects and tells the server which policy to load: **each PC chooses the policy**, so every
student's `.env` needs the same `POLICY_PATH`. The server downloads it from the Hub (first time only) and
loads it onto the GPU. Then the loop starts: the client streams observations, the server returns chunks of
`ACTIONS_PER_CHUNK` actions, and the client executes them at 30 Hz. When the queue drops below
`CHUNK_SIZE_THRESHOLD` × chunk size, it sends a new observation. Each new chunk **replaces** the queue:
actions whose time has passed are skipped, overlapping steps are blended (`AGGREGATE_FN`, default
`weighted_average` = 0.3 old + 0.7 new), and leftover old steps are dropped.

**What `scripts/robot_client.py` changes** compared with `python -m lerobot.async_inference.robot_client`:
1. It registers the `zmq` camera type. LeRobot 0.6.1's robot client forgets to, and fails with
   `Couldn't find a choice class for 'zmq'`.
2. It uploads observations in a background thread. Stock LeRobot uploads each ~1.8 MB observation (two
   raw 640×480 images) *inside* the 30 Hz control loop and waits for it: on Wi-Fi that froze the arm for
   60–100 ms per upload (a visible stutter, ~24 Hz instead of 30). Now the loop never waits; if an upload
   is still running, a newer observation replaces the waiting one. `ASYNC_SEND=0` restores the original.
3. `DEBUG_QUEUE=1 scripts/11_robot_client.sh` logs every chunk merge: which steps were stale, blended or
   dropped, and `max_jump`, the largest disagreement (degrees) between the old and new plan. Big jumps
   mean the policy keeps changing its mind, typical in a scene unlike its training data.

Every run writes a full debug log to `logs/robot_client_<time>.log`, inside the folder you ran the
script from (`scripts/logs/` if you run `./11_robot_client.sh` from `scripts/`). Its `Control loop (ms)` lines
should stay well under 33 ms.

Tuning:
| Symptom | Try |
|---|---|
| Arm pauses between chunks (queue runs empty) | raise `CHUNK_SIZE_THRESHOLD` (0.6–0.7) or `ACTIONS_PER_CHUNK` |
| Arm reacts late / overshoots | lower `ACTIONS_PER_CHUNK` |
| Arm hesitates / goes back to earlier positions | check `DEBUG_QUEUE=1` for big `max_jump`; try `AGGREGATE_FN=average` or `conservative`. Usually the policy is outside its training scene: rebuild its scene, or record your own data and fine-tune |
| Gripper turns sideways / wrong rotation at start | `wrist_roll` zero differs from the policy's: recalibrate (§5.2) |
| Arm jumps to a pose when inference starts | the first chunk starts from the policy's training start pose. Move the arm close to that pose before starting |
| Connection refused | server running? `SPARK_HOST`/`POLICY_SERVER_PORT` right? Test with `nc -z <SPARK_HOST> 8090`. Refused right after a previous session: the server is restarting, wait a few seconds and retry. Firewall: `sudo ufw allow 8090/tcp` on the Spark |

A wired Ethernet connection (PC and Spark on the same router or switch) makes new chunks arrive sooner
than over Wi-Fi. Check which link the PC actually uses with `route get <SPARK_HOST> | grep interface`
(on a MacBook Air, `en0` is Wi-Fi).

**Safety:** the first runs of any new policy can move fast and unexpectedly. Keep the workspace clear and
a hand on the follower's power supply. Ctrl+C stops the client; torque is released on disconnect.

**Optional: run without the Spark.** For a small policy such as ACT on a Mac:
`scripts/12_rollout_local.sh mps` (uses `lerobot-rollout`, all on the PC, 60 s per run). VLAs are too slow
for this on a laptop.

---

## 11. Troubleshooting

| Problem | Cause / fix |
|---|---|
| `Permission denied: /dev/ttyACM0` (Linux) | `sudo usermod -aG dialout $USER` and re-login, or the udev rule's `MODE="0666"` |
| Motor not found / wrong ID | loose daisy-chain cable, or the arm's power supply is off |
| Follower moves differently from leader | re-calibrate both; check `FOLLOWER_ID`/`LEADER_ID` didn't change |
| `ZMQCamera … timeout` | camera server not running, or wrong `CAMERA_SERVER_HOST`/ports |
| Views swapped | camera indices changed; re-run step 6 and look at `snapshots/` |
| Policy server: feature mismatch | camera names/count/resolution ≠ what the policy expects; compare `CAM1_NAME`/`CAM2_NAME` and resolution with its `config.json` (§9) |
| torchcodec `Could not load libtorchcodec` (macOS) | Homebrew's `ffmpeg` is 9+, torchcodec supports 4–8: `brew install ffmpeg@8`. The scripts set `DYLD_FALLBACK_LIBRARY_PATH`; export it yourself to run `lerobot-*` by hand |
| `objc … Class AVFFrameReceiver is implemented in both …` (macOS) | harmless: PyAV, OpenCV and FFmpeg each bundle the same library. Ignore it |
| Episodes shorter than your session | `EPISODE_TIME_S` cuts the recording into episodes (§8) |
| Recording keys don't work (macOS) | grant Accessibility / Input Monitoring to your terminal; keep the terminal focused |
| torchcodec `libnppicc.so.13` / `libnvrtc` errors in a custom image | aarch64 torchcodec is a CUDA build: install `nvidia-npp==13.0.*` and set `LD_LIBRARY_PATH` as in the Dockerfiles |
| Policy server keeps `Restarting`, log says `Address already in use` | another program uses the port. Find it with `sudo ss -ltnp \| grep :<port>` (on a shared machine, 8080 is often taken). Change `POLICY_SERVER_PORT` in the **Spark's** `/home/academy/SO101/.env`, then `docker compose -f compose.spark.yml restart policy-server`, and use the same port on every PC |
| `Couldn't find a choice class for 'zmq'` | you ran LeRobot's robot client directly; use `scripts/11_robot_client.sh` (§10) |
| `adduser: Please enter a username matching …` | Linux usernames must be lowercase: `academy`, not `ACADEMY` |
| `sudo: a terminal is required to read the password` during `rsync --rsync-path="sudo …"` | copy to your own home first, then `sudo cp` as in §9.2 |

---

## 12. What has been verified

Tested on this repo (macOS arm64 host, no robot attached):
- `requirements/*.txt` resolve for macOS arm64, Linux x86_64 (CPU torch) and Linux aarch64 + CUDA 13 (Spark).
- Both images build (on arm64, the Spark's architecture). Inside them `lerobot-info` runs, and torch,
  torchcodec, SmolVLA and the policy server import correctly.
- Camera server → LeRobot `ZMQCamera`: correct per-camera view, colours and size, 30 fps.
- LeRobot 0.6.1 parses the exact `--robot.cameras` strings the scripts build, for both `lerobot-record`
  and the async robot client. The policy server starts and listens.

Tested on the real setup (MacBook Air on Wi-Fi + Academy DGX Spark, `academy` user):
- Spark image built (6.9 GB), GPU check passes (`NVIDIA GB10`, `GPU matmul ok`); policy server on 8090.
- `scripts/11_robot_client.sh` with `BoyuZhao/so101-act-pick-and-place`: cameras, follower and server
  connect, the policy loads on the GPU and drives the arm. With the background upload, 0 of 742 control
  loop iterations went over the 33 ms budget (max 7.8 ms), against 457 of 2935 (max 544 ms) without it.
- The pretrained policy makes progress on the task but isn't reliable in our scene (it goes back to
  earlier positions): next step is collecting our own data and fine-tuning on it.

Not yet verified by someone following this guide from scratch: the PC setup (§4) on a fresh machine, and
the Spark setup (§9.1–9.2) by a new user.

---

## License

Apache License 2.0 (see [LICENSE](LICENSE)), the same license as [LeRobot](https://github.com/huggingface/lerobot),
which this project builds on. Pretrained policies and datasets from the Hugging Face Hub keep their own licenses.
