#!/usr/bin/env bash
# Step 6 — Move the leader, the follower copies it. Practise the task here before recording.
#   usage: scripts/06_teleoperate.sh [--no-cameras]
source "$(dirname "$0")/lib.sh"
CAM_ARGS=(--robot.cameras="$(cameras_arg)" --display_data="$DISPLAY_DATA")
[[ "${1:-}" == "--no-cameras" ]] && CAM_ARGS=()
run lerobot-teleoperate \
  --robot.type=so101_follower --robot.port="$FOLLOWER_PORT" --robot.id="$FOLLOWER_ID" --robot.use_degrees="$USE_DEGREES" \
  --teleop.type=so101_leader --teleop.port="$LEADER_PORT" --teleop.id="$LEADER_ID" --teleop.use_degrees="$USE_DEGREES" \
  ${CAM_ARGS[@]+"${CAM_ARGS[@]}"}
