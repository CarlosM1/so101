"""Grab one frame per camera THROUGH LeRobot's ZMQCamera and save it as a JPEG.

This tests the exact path the recorder and the robot client use, so if the snapshots look
right (correct view per name, correct colours, correct size) your camera setup is right.

    python camera_server/snapshot.py --host 127.0.0.1 --camera camera1:5555 --camera camera2:5556
"""

import argparse
from pathlib import Path

import cv2
from lerobot.cameras.zmq import ZMQCamera, ZMQCameraConfig


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--camera", action="append", required=True, metavar="NAME:PORT")
    p.add_argument("--out", default="snapshots")
    args = p.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for spec in args.camera:
        name, port = spec.rsplit(":", 1)
        cam = ZMQCamera(ZMQCameraConfig(server_address=args.host, port=int(port), camera_name=name))
        cam.connect()
        frame = cam.read()  # RGB, (H, W, 3)
        cam.disconnect()
        path = out / f"{name}.jpg"
        cv2.imwrite(str(path), cv2.cvtColor(frame, cv2.COLOR_RGB2BGR))  # imwrite wants BGR
        print(f"{name}: {frame.shape[1]}x{frame.shape[0]} -> {path}")


if __name__ == "__main__":
    main()
