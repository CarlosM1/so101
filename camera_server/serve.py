"""SO101 camera server.

Opens each USB camera ONCE and publishes its frames over ZeroMQ, so that any number of
processes (teleop, recording, the robot client, a debug viewer...) can use the cameras at
the same time, locally or over the network. LeRobot consumes the stream with its built-in
`ZMQCamera` (`--robot.cameras="{camera1: {type: zmq, server_address: ..., port: ...}}"`).

Wire format (what lerobot.cameras.zmq.ZMQCamera expects), one JSON string per message:
    {"timestamps": {"<camera_name>": <unix time>}, "images": {"<camera_name>": "<base64 JPEG>"}}

Design choices worth knowing:
  * ONE PUB socket (port) PER CAMERA. ZMQCamera falls back to "the first image in the
    message" when its camera name is missing, so sharing a port between cameras running at
    slightly different rates can silently hand you the wrong view.
  * Capture and JPEG encoding happen in a background thread per camera; the publisher
    only ever sends the latest frame (stale frames are dropped, never queued).
  * Colour: frames are captured as RGB. cv2.imencode assumes BGR, and the client's
    cv2.imdecode returns the same channel order, so RGB survives the round trip unchanged.
    That is exactly what LeRobot's own image_server does; don't "fix" it with cvtColor.

Usage:
    python camera_server/serve.py --camera camera1=0:5555 --camera camera2=1:5556 \
        --width 640 --height 480 --fps 30

    DEVICE may be an OpenCV index (0), a path (/dev/video0), or `test:<colour>` (e.g. test:red)
    for a synthetic camera, so you can test the pipeline before any camera is plugged in.
"""

from __future__ import annotations

import argparse
import base64
import json
import logging
import signal
import threading
import time

import cv2
import numpy as np
import zmq
from lerobot.cameras import ColorMode
from lerobot.cameras.opencv import OpenCVCamera, OpenCVCameraConfig

log = logging.getLogger("camera_server")


class TestPatternCamera:
    """Stand-in for OpenCVCamera: a solid colour with a moving white bar, at the requested fps."""

    COLOURS = {"red": (255, 0, 0), "green": (0, 255, 0), "blue": (0, 0, 255), "gray": (128, 128, 128)}

    def __init__(self, colour: str, width: int, height: int, fps: int):
        self.width, self.height, self.fps = width, height, fps
        self._base = np.full((height, width, 3), self.COLOURS.get(colour, (128, 128, 128)), np.uint8)
        self._i = 0
        self._next = time.perf_counter()

    def connect(self) -> None:
        pass

    def read(self) -> np.ndarray:  # RGB, like OpenCVCamera with ColorMode.RGB
        self._next += 1.0 / self.fps  # fixed schedule, so encode time doesn't lower the fps
        time.sleep(max(0.0, self._next - time.perf_counter()))
        frame = self._base.copy()
        x = (self._i * 8) % self.width
        frame[:, x : x + 8] = 255
        self._i += 1
        return frame

    def disconnect(self) -> None:
        pass


class CameraPublisher:
    """Capture thread + ZMQ publisher for a single camera."""

    def __init__(self, ctx: zmq.Context, name: str, device: int | str, port: int, args: argparse.Namespace):
        self.name, self.port = name, port
        self.fps = args.fps
        self.quality = args.jpeg_quality
        if isinstance(device, str) and device.startswith("test:"):
            self.camera = TestPatternCamera(device[5:], args.width, args.height, args.fps)
        else:
            self.camera = OpenCVCamera(
                OpenCVCameraConfig(
                    index_or_path=device,
                    width=args.width,
                    height=args.height,
                    fps=args.fps,
                    fourcc=args.fourcc or None,
                    color_mode=ColorMode.RGB,
                )
            )
        self.socket = ctx.socket(zmq.PUB)
        self.socket.setsockopt(zmq.SNDHWM, 2)  # never build a backlog of old frames
        self.socket.setsockopt(zmq.LINGER, 0)
        self.socket.bind(f"tcp://{args.bind}:{port}")

        self._lock = threading.Lock()
        self._latest: tuple[str, float] | None = None
        self._stop = threading.Event()
        self.frames_captured = 0

    def start(self) -> None:
        self.camera.connect()
        log.info("%s: device opened %sx%s@%s -> tcp://*:%s", self.name, self.camera.width,
                 self.camera.height, self.fps, self.port)
        threading.Thread(target=self._capture_loop, name=f"{self.name}-capture", daemon=True).start()
        threading.Thread(target=self._publish_loop, name=f"{self.name}-publish", daemon=True).start()

    def _capture_loop(self) -> None:
        while not self._stop.is_set():
            try:
                frame = self.camera.read()  # blocks at the camera's native rate
                ts = time.time()
                ok, jpg = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), self.quality])
                if not ok:
                    continue
                with self._lock:
                    self._latest = (base64.b64encode(jpg).decode("ascii"), ts)
                self.frames_captured += 1
            except Exception as e:  # keep serving even if one read fails
                log.warning("%s: capture error: %s", self.name, e)
                time.sleep(0.05)

    def _publish_loop(self) -> None:
        last_ts = 0.0
        period = 1.0 / self.fps
        while not self._stop.is_set():
            t0 = time.perf_counter()
            with self._lock:
                latest = self._latest
            if latest is not None and latest[1] > last_ts:
                img, ts = latest
                msg = json.dumps({"timestamps": {self.name: ts}, "images": {self.name: img}})
                try:
                    self.socket.send_string(msg, zmq.NOBLOCK)
                except zmq.Again:
                    pass  # no subscriber keeping up; drop the frame
                last_ts = ts
            time.sleep(max(0.0, period - (time.perf_counter() - t0)))

    def stop(self) -> None:
        self._stop.set()
        time.sleep(0.1)
        try:
            self.camera.disconnect()
        except Exception:
            pass
        self.socket.close()


def parse_camera(spec: str) -> tuple[str, int | str, int]:
    """'camera1=0:5555' -> ('camera1', 0, 5555); devices may also be paths like /dev/video0."""
    name, rest = spec.split("=", 1)
    device, port = rest.rsplit(":", 1)
    return name, int(device) if device.isdigit() else device, int(port)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--camera", action="append", required=True, metavar="NAME=DEVICE:PORT")
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=480)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--fourcc", default="", help='e.g. "MJPG" on Linux; leave empty on macOS')
    p.add_argument("--jpeg-quality", type=int, default=90)
    p.add_argument("--bind", default="*", help="interface to listen on (* = all)")
    args = p.parse_args()
    # force=True: importing lerobot already installed a root handler, which would make this a no-op.
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", force=True)

    ctx = zmq.Context()
    pubs = [CameraPublisher(ctx, *parse_camera(s), args=args) for s in args.camera]
    for pub in pubs:
        pub.start()

    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    log.info("Serving %d camera(s). Ctrl+C to stop.", len(pubs))
    last = {p.name: 0 for p in pubs}
    while not stop.wait(5.0):
        rates = []
        for pub in pubs:
            rates.append(f"{pub.name}={(pub.frames_captured - last[pub.name]) / 5.0:.1f}fps")
            last[pub.name] = pub.frames_captured
        log.info("capture rates: %s", "  ".join(rates))

    for pub in pubs:
        pub.stop()
    ctx.term()


if __name__ == "__main__":
    main()
