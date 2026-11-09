#!/usr/bin/env bash
# Step 10 (SPARK) — Start the gRPC policy server. It loads the policy the robot client asks for.
source "$(dirname "$0")/lib.sh"
run python -m lerobot.async_inference.policy_server \
  --host=0.0.0.0 --port="$POLICY_SERVER_PORT" --fps="$CAMERA_FPS"
