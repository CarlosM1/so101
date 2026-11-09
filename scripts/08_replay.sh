#!/usr/bin/env bash
# Replay a recorded episode on the follower: proves the dataset's actions are sane.
#   usage: scripts/08_replay.sh [EPISODE_INDEX]
source "$(dirname "$0")/lib.sh"
run lerobot-replay \
  --robot.type=so101_follower --robot.port="$FOLLOWER_PORT" --robot.id="$FOLLOWER_ID" --robot.use_degrees="$USE_DEGREES" \
  --dataset.repo_id="$DATASET_REPO_ID" --dataset.root="$HF_LEROBOT_HOME/$DATASET_REPO_ID" \
  --dataset.episode="${1:-0}"
