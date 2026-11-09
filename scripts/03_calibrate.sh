#!/usr/bin/env bash
# Step 3 — Calibrate: put every joint at mid-range, Enter, then sweep each joint through its full range.
# The result is saved as $HF_LEROBOT_HOME/calibration/{robots/so_follower,teleoperators/so_leader}/<ID>.json
#   usage: scripts/03_calibrate.sh follower|leader
source "$(dirname "$0")/lib.sh"
case "${1:-}" in
  follower) run lerobot-calibrate --robot.type=so101_follower --robot.port="$FOLLOWER_PORT" --robot.id="$FOLLOWER_ID" ;;
  leader)   run lerobot-calibrate --teleop.type=so101_leader --teleop.port="$LEADER_PORT" --teleop.id="$LEADER_ID" ;;
  *) echo "usage: $0 follower|leader" >&2; exit 2 ;;
esac
echo; echo "Calibration files:"; find "$HF_LEROBOT_HOME/calibration" -name '*.json' -print
