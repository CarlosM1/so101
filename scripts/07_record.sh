#!/usr/bin/env bash
# Step 7 — Record demonstrations with the leader arm.
#   usage: scripts/07_record.sh            new dataset  (NUM_EPISODES episodes)
#          scripts/07_record.sh --resume   append NUM_EPISODES more episodes to the existing one
# Keys (terminal must be focused):  → / n  finish episode early   ← / r  redo episode   Esc / q  stop & save
source "$(dirname "$0")/lib.sh"
DATASET_DIR="$HF_LEROBOT_HOME/$DATASET_REPO_ID"
EXTRA=()
if [[ "${1:-}" == "--resume" ]]; then
  EXTRA=(--resume=true --dataset.root="$DATASET_DIR")
elif [[ -d "$DATASET_DIR" ]]; then
  echo "Dataset already exists at $DATASET_DIR" >&2
  echo "Use --resume to add episodes, or change DATASET_NAME in .env." >&2
  exit 1
fi
[[ -n "${IN_DOCKER:-}" ]] && EXTRA+=(--play_sounds=false)
run lerobot-record \
  --robot.type=so101_follower --robot.port="$FOLLOWER_PORT" --robot.id="$FOLLOWER_ID" --robot.use_degrees="$USE_DEGREES" \
  --robot.cameras="$(cameras_arg)" \
  --teleop.type=so101_leader --teleop.port="$LEADER_PORT" --teleop.id="$LEADER_ID" --teleop.use_degrees="$USE_DEGREES" \
  --display_data="$DISPLAY_DATA" \
  --dataset.repo_id="$DATASET_REPO_ID" \
  --dataset.no_stamp=true \
  --dataset.single_task="$TASK" \
  --dataset.fps="$CAMERA_FPS" \
  --dataset.num_episodes="$NUM_EPISODES" \
  --dataset.episode_time_s="$EPISODE_TIME_S" \
  --dataset.reset_time_s="$RESET_TIME_S" \
  --dataset.push_to_hub="$PUSH_TO_HUB" \
  --dataset.streaming_encoding=true \
  --dataset.encoder_threads=2 \
  ${EXTRA[@]+"${EXTRA[@]}"}
echo "Local dataset: $DATASET_DIR"
if [[ "$PUSH_TO_HUB" == "true" ]]; then echo "Hub:           https://huggingface.co/datasets/$DATASET_REPO_ID"; fi
