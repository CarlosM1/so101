#!/usr/bin/env bash
# Optional (PC) — Run the policy ON THE PC, no Spark. Fine for ACT on Apple MPS; too slow for most VLAs.
#   usage: scripts/12_rollout_local.sh [DEVICE]   (mps | cpu | cuda, default mps)
source "$(dirname "$0")/lib.sh"
run lerobot-rollout \
  --strategy.type=base \
  --policy.path="$POLICY_PATH" \
  --device="${1:-mps}" \
  --robot.type=so101_follower --robot.port="$FOLLOWER_PORT" --robot.id="$FOLLOWER_ID" --robot.use_degrees="$USE_DEGREES" \
  --robot.cameras="$(cameras_arg)" \
  --task="$TASK" \
  --fps="$CAMERA_FPS" \
  --duration=60
