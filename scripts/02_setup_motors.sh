#!/usr/bin/env bash
# Step 2 — Write motor IDs (1..6) and baudrate into each servo's EEPROM. ONCE per arm, ever.
# Connect ONE motor at a time when prompted (gripper first -> id 6 ... shoulder_pan -> id 1).
#   usage: scripts/02_setup_motors.sh follower|leader
source "$(dirname "$0")/lib.sh"
case "${1:-}" in
  follower) run lerobot-setup-motors --robot.type=so101_follower --robot.port="$FOLLOWER_PORT" ;;
  leader)   run lerobot-setup-motors --teleop.type=so101_leader --teleop.port="$LEADER_PORT" ;;
  *) echo "usage: $0 follower|leader" >&2; exit 2 ;;
esac
