#!/usr/bin/env bash
# Step 5 — Start the camera server (leave it running in its own terminal).
source "$(dirname "$0")/lib.sh"
run python "$PROJECT_ROOT/camera_server/serve.py" \
  --camera "${CAM1_NAME}=${CAM1_DEVICE}:${CAM1_PORT}" \
  --camera "${CAM2_NAME}=${CAM2_DEVICE}:${CAM2_PORT}" \
  --width "$CAMERA_WIDTH" --height "$CAMERA_HEIGHT" --fps "$CAMERA_FPS" \
  --fourcc "${CAMERA_FOURCC:-}"
