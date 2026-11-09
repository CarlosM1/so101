#!/usr/bin/env bash
# Check the camera server the way LeRobot sees it: writes snapshots/<CAM1_NAME>.jpg and <CAM2_NAME>.jpg.
source "$(dirname "$0")/lib.sh"
cd "$PROJECT_ROOT"
run python camera_server/snapshot.py --host "$CAMERA_SERVER_HOST" \
  --camera "${CAM1_NAME}:${CAM1_PORT}" --camera "${CAM2_NAME}:${CAM2_PORT}"
